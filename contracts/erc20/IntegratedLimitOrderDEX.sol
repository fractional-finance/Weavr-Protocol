// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";

error ZeroPrice();
error ZeroAmount();
error EOABuyer(address buyer);
error NotWhitelistedBuyer(address buyer);
error LessThanMinimumAmount(uint256 amount, uint256 minimumAmount);
error NotEnoughFunds(uint256 required, uint256 balance);
error NullOrder();
error NotOrderTrader(address caller, address trader);

abstract contract IntegratedLimitOrderDEX is Initializable, ReentrancyGuardUpgradeable, IIntegratedLimitOrderDEX {
  using SafeERC20 for IERC20;

  // Token to trade against, presumably a USD stablecoin or WETH
  address public dexToken;

  // Locked funds of the token this is integrated into
  mapping(address => uint256) public locked;

  struct Order {
    address trader;
    uint256 amount;
  }

  struct PricePoint {
    OrderType orderType;
    Order[] orders;
  }

  // Indexed by price
  mapping (uint256 => PricePoint) private _points;

  function whitelisted(address person) public view virtual returns (bool);
  function _transfer(address from, address to, uint256 amount) internal virtual;
  function balanceOf(address account) public virtual returns (uint256);

  function __IntegratedLimitOrderDEX_init(address _dexToken) internal onlyInitializing {
    __ReentrancyGuard_init();
    dexToken = _dexToken;
  }

  // Fill an order
  function fill(
    bool buying,
    address trader,
    uint256 amount,
    uint256 price,
    PricePoint storage point
  ) private returns (uint256) {
    // Fill orders until there are either no orders or our order is filled
    uint256 filled = 0;
    uint256 h = 0;
    for (; (h < point.orders.length) && (amount != 0); h++) {
      uint256 thisAmount = point.orders[h].amount;
      if (thisAmount > amount) {
        thisAmount = amount;
      }
      point.orders[h].amount -= thisAmount;
      filled += thisAmount;
      amount -= thisAmount;
      emit Filled(trader, point.orders[h].trader, price, amount);

      if (buying) {
        IERC20(dexToken).safeTransfer(point.orders[h].trader, price * thisAmount);
        _transfer(point.orders[h].trader, trader, thisAmount);
        locked[point.orders[h].trader] -= thisAmount;
      } else {
        _transfer(trader, point.orders[h].trader, thisAmount);
        locked[trader] -= thisAmount;
      }
    }

    // Transfer the DEX token sum if selling
    if (!buying) {
      IERC20(dexToken).safeTransfer(trader, filled * price);
    }

    // h will always be after the last edited order
    h--;

    // This crux order may have been partially filled or fully filled
    // If it's partially filled, decrement again
    if (point.orders[h].amount != 0) {
      // Prevents reversion by underflow
      // If we didn't fill any orders, there's nothing left to do
      if (h == 0) {
        return filled;
      }
      h--;
    }

    // If we filled every order, set the order type to null
    if (h == (point.orders.length - 1)) {
      point.orderType = OrderType.Null;
      // Clear the orders array
      // For now, this also offers a gas refund, yet future EIPs will likely remove this
      while (point.orders.length != 0) {
        point.orders.pop();
      }
    } else {
      // Do a O(1) deletion from the orders array for each filled order
      // A shift would be very expensive and the 18 decimal accuracy of Ethereum means preserving the order of orders wouldn't be helpful
      // 1 wei is microscopic, so placing a 1 wei different order...
      for (uint256 i = 0; i <= h; i++) {
        if ((h + i) < point.orders.length) {
          point.orders[i] = point.orders[point.orders.length - 1];
        }
        point.orders.pop();
      }
    }

    return filled;
  }

  // nonReentrant to prevent the same order from being filled multiple times
  // Returns the amount of tokens filled and the position of the created order, if one exists
  // If the amount filled is equivalent to the amount, the position will be 0
  function action(
    OrderType current,
    OrderType other,
    address trader,
    uint256 price,
    uint256 amount
  ) private nonReentrant returns (uint256 filled, uint256) {
    if (price == 0) {
      revert ZeroPrice();
    }
    if (amount == 0) {
      revert ZeroAmount();
    }

    PricePoint storage point = _points[price];
    // If there's counter orders at this price, fill them
    if (point.orderType == other) {
      filled = fill(current == OrderType.Buy, trader, price, amount, point);
      // Return if fully filled
      if (filled == amount) {
        return (filled, 0);
      }
      amount -= filled;
    }

    // If there's nothing at this price point, naturally or due to filling orders, set it
    if (point.orderType == OrderType.Null) {
      point.orderType = current;
      emit NewOrder(current, price);
    }

    // Add the new order
    // We could also merge orders here, if an existing order at this price point existed
    point.orders.push(Order(trader, amount));
    emit OrderIncrease(trader, price, amount);

    return (filled, point.orders.length - 1);
  }

  // Lets a trader to be specified as the receiver of the tokens in question
  // This functionality is required by the DEXRouter and this remains secure thanks to payment being from msg.sender
  // Returns the same as action
  function buy(
    address trader,
    uint256 payment,
    uint256 price,
    uint256 minimumAmount
  ) external override returns (uint256, uint256) {
    // Require this be called by a contract
    // Prevents anyone from building a UX which doesn't utilize DEXRouter
    // While someone could write a different contract, anyone doing that is trusted to know what they're doing
    // See DEXRouter for why this is so important
    // This is moving JS responsibilities into Solidity, which isn't optimal due to gas costs,
    // yet this is a potentially critical bug which someone may fall past if trying to move quickly
    if (!AddressUpgradeable.isContract(msg.sender)) {
      // This should be incredibly obvious
      revert EOABuyer(msg.sender);
    }

    // Make sure they're whitelisted so trade execution won't fail
    // This would be a DoS if it was allowed to place a standing order at this price point
    // It would be allowed to as long as it didn't error before hand by filling an order
    // No orders, no filling, no error
    if (!whitelisted(trader)) {
      revert NotWhitelistedBuyer(trader);
    }
    // Support fee on transfer tokens
    // Safe against re-entrancy as action has nonReentrant
    // cancelOrder could also be called which could lower the balance considered received
    // That isn't exploitable thanks to Solidity 0.8 making all math underflow checked
    // (without utilizing unchecked, which isn't present here)
    // The Crowdfund contract actually verifies its token isn't fee on transfer
    // The Thread initializer uses the same token for both that and this
    // That said, any token which can have its fee set may be set to 0 during Crowdfund,
    // allowing it to pass, yet set to non-0 later in its life, causing this to fail
    // USDT notably has fee on transfer code, currently set to 0, that may someday activate
    uint256 balance = IERC20(dexToken).balanceOf(address(this));
    IERC20(dexToken).safeTransferFrom(msg.sender, address(this), payment);
    uint256 received = IERC20(dexToken).balanceOf(address(this)) - balance;
    uint256 amount = received / price;
    if (amount < minimumAmount) {
      revert LessThanMinimumAmount(amount, minimumAmount);
    }

    // Dust may exist in the form of received - (price * amount) thanks to rounding errors
    // While this likely isn't worth the gas it would cost to transfer it, do so to ensure correctness
    uint256 dust = received - (price * amount);
    if (received != 0) {
      // Transfer to the trader as msg.sender is presumably a router contract which shouldn't hold funds
      // If a non-router contract trades on this DEX, it should specify itself as the trader, making this still valid
      // If this was directly chained into Uniswap though to execute a trade there, then this dust would effectively be burnt
      // It's insignificant enough to not bother adding an extra argument for that niche use case
      IERC20(dexToken).safeTransfer(trader, dust);
    }

    return action(OrderType.Buy, OrderType.Sell, trader, price, amount);
  }

  function sell(uint256 price, uint256 amount) external override returns (uint256, uint256) {
    locked[msg.sender] += amount;
    if (balanceOf(msg.sender) < locked[msg.sender]) {
      revert NotEnoughFunds(locked[msg.sender], balanceOf(msg.sender));
    }
    return action(OrderType.Sell, OrderType.Buy, msg.sender, price, amount);
  }

  function cancelOrder(uint256 price, uint256 i) external override {
    PricePoint storage point = _points[price];
    // This latter case is handled by Solidity's native bounds checks
    // Technically, since a Null OrderType means orders.length is 0, this entire if check is meaningless
    // Kept for robustness
    if ((point.orderType == OrderType.Null) || (point.orders.length <= i)) {
      revert NullOrder();
    }
    if (point.orders[i].trader != msg.sender) {
      revert NotOrderTrader(msg.sender, point.orders[i].trader);
    }

    uint256 amount = point.orders[i].amount;
    // If this is not the last order, shift the last order down
    if (i != (point.orders.length - 1)) {
      point.orders[i] = point.orders[point.orders.length - 1];
    }
    point.orders.pop();

    // Safe to re-enter as the order has already been deleted
    if (point.orderType == OrderType.Buy) {
      IERC20(dexToken).safeTransfer(msg.sender, amount * price);
    } else if (point.orderType == OrderType.Sell) {
      locked[msg.sender] -= amount;
    }
  }

  function getPointType(uint256 price) external view override returns (uint256) {
    return uint256(_points[price].orderType);
  }

  function getOrderQuantity(uint256 price) external view override returns (uint256) {
    return _points[price].orders.length;
  }

  function getOrderTrader(uint256 price, uint256 i) external view override returns (address) {
    return _points[price].orders[i].trader;
  }

  function getOrderAmount(uint256 price, uint256 i) external view override returns (uint256) {
    return _points[price].orders[i].amount;
  }
}
