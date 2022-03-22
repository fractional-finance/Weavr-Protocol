// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";
import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";

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
  function decimals() public virtual returns (uint8);

  function __IntegratedLimitOrderDEX_init(address _dexToken) internal onlyInitializing {
    __ReentrancyGuard_init();
    dexToken = _dexToken;
  }

  // Convert a token quantity to atomic units
  function atomic(uint256 amount) public override returns (uint256) {
    return amount * (10 ** decimals());
  }

  // Fill orders
  function fill(
    bool buying,
    address trader,
    uint256 price,
    uint256 amount,
    PricePoint storage point
  ) private returns (uint256) {
    // Fill orders until there are either no orders or our order is filled
    uint256 filled = 0;
    uint256 h = 0;
    for (; (h < point.orders.length) && (amount != 0); h++) {
      // Trader was removed. Delete their order and move on
      // Technically this is an interaction, and check, in the middle of effects
      // This function is view meaning its only risk is calling the DEX and viewing
      // an invalid partial state to make its decision on if the trader is whitelisted
      // This function is trusted code, and here it is trusted to not be idiotic
      if (!whitelisted(point.orders[h].trader)) {
        if (h != point.orders.length - 1) {
          point.orders[h] = point.orders[point.orders.length - 1];
          point.orders.pop();
        }
        continue;
      }

      uint256 thisAmount = point.orders[h].amount;
      if (thisAmount > amount) {
        thisAmount = amount;
      }
      point.orders[h].amount -= thisAmount;
      filled += thisAmount;
      amount -= thisAmount;
      emit Filled(trader, point.orders[h].trader, price, amount);

      uint256 atomicAmount = atomic(thisAmount);
      if (buying) {
        IERC20(dexToken).safeTransfer(point.orders[h].trader, price * thisAmount);
        _transfer(point.orders[h].trader, trader, atomicAmount);
        locked[point.orders[h].trader] -= atomicAmount;
      } else {
        _transfer(trader, point.orders[h].trader, atomicAmount);
        locked[trader] -= atomicAmount;
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

  // Returns the amount of tokens filled and the position of the created order, if one exists
  // If the amount filled is equivalent to the amount, the position will be 0
  function action(
    OrderType current,
    OrderType other,
    address trader,
    uint256 price,
    uint256 amount
  ) private returns (uint256 filled, uint256) {
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
  // minimumAmount is in whole tokens (presumably 1e18 atomic units)
  function buy(
    address trader,
    uint256 payment,
    uint256 price,
    uint256 minimumAmount
  ) external override nonReentrant returns (uint256, uint256) {
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
      revert NotWhitelisted(trader);
    }

    // Support fee on transfer tokens
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

  // amount is in 'whole' tokens (1e18)
  function sell(uint256 price, uint256 amount) external override nonReentrant returns (uint256, uint256) {
    locked[msg.sender] += atomic(amount);
    if (balanceOf(msg.sender) < locked[msg.sender]) {
      revert NotEnoughFunds(locked[msg.sender], balanceOf(msg.sender));
    }
    return action(OrderType.Sell, OrderType.Buy, msg.sender, price, amount);
  }

  // Doesn't require nonReentrant as all interactions are after checks and effects
  // Has nonReentrant to be safe
  function cancelOrder(uint256 price, uint256 i) external override nonReentrant {
    PricePoint storage point = _points[price];
    // This latter case is handled by Solidity's native bounds checks
    // Technically, since a Null OrderType means orders.length is 0, this entire if check is meaningless
    // Kept for robustness
    if ((point.orderType == OrderType.Null) || (point.orders.length <= i)) {
      revert NullOrder();
    }

    // Copy the order to memory
    Order memory order = point.orders[i];
    // If this is not the last order, shift the last order down
    if (i != (point.orders.length - 1)) {
      point.orders[i] = point.orders[point.orders.length - 1];
    }
    // Delete the order
    point.orders.pop();

    // If the trader isn't whitelisted, meaning they were removed, return the counter token
    // This allows anyone to cancel orders of those who were banned from the protocol
    // Technically an interaction, yet whitelisted is trusted
    // It should be noted that the effect of the order in question already having been deleted has happened
    if (!whitelisted(order.trader)) {
      // Safe to re-enter as the order has already been deleted
      if (point.orderType == OrderType.Buy) {
        IERC20(dexToken).safeTransfer(order.trader, price * order.amount);
      }
      return;
    }

    // If the trader in question wasn't removed, ensure they were the actually
    // the ones to cancel this order
    // While generally these checks should be done before effects (deletion),
    // the entire transaction will still revert without issue and this is the cleanest
    // way to write the code given the requirement of anyone being able to cancel
    // orders of those not whitelisted
    // Also, no interactions have happened since the effects occurred
    if (order.trader != msg.sender) {
      revert NotOrderTrader(msg.sender, point.orders[i].trader);
    }

    if (point.orderType == OrderType.Sell) {
      locked[order.trader] -= atomic(order.amount);
    // Technically, this can re-enter (ignoring nonReentrant) and when doing so flip the OrderType to Sell
    // That wouldn't be an issue since this is `if {} else if`, yet would be an issue if `if {} if`
    // Still placing Buy second for peace of mind
    } else if (point.orderType == OrderType.Buy) {
      IERC20(dexToken).safeTransfer(order.trader, price * order.amount);
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
    Order memory order = _points[price].orders[i];
    if (!whitelisted(order.trader)) {
      return 0;
    }
    return order.amount;
  }
}
