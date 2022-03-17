// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";

// Doesn't support fee on transfer/rebase yet various USD stablecoins do theoretically have fee on transfer
// Either add an explicit require for non-fee on transfer or support fee on transfer?
// TODO
abstract contract IntegratedLimitOrderDEX is IIntegratedLimitOrderDEX, Initializable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  // Token to trade against, presumably a USD stablecoin or WETH
  address public dexToken;

  // Locked funds of the token this is integrated into
  mapping(address => uint256) public locked;

  enum OrderType { Null, Buy, Sell }
  struct Order {
    address holder;
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
  function fill(bool buying, uint256 amount, uint256 price, PricePoint storage point) private returns (uint256) {
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
      emit Filled(msg.sender, point.orders[h].holder, price, amount);

      if (buying) {
        IERC20(dexToken).safeTransfer(point.orders[h].holder, price * thisAmount);
        _transfer(point.orders[h].holder, msg.sender, thisAmount);
        locked[point.orders[h].holder] -= thisAmount;
      } else {
        _transfer(msg.sender, point.orders[h].holder, thisAmount);
        locked[msg.sender] -= thisAmount;
      }
    }

    // Transfer the DEX token sum if selling
    if (!buying) {
      IERC20(dexToken).safeTransfer(msg.sender, filled * price);
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
      // Clear the holders array
      // For now, this also offers a gas refund, yet future EIPs will likely remove this
      while (point.orders.length != 0) {
        point.orders.pop();
      }
    } else {
      // Do a O(1) deletion from the holders array for each filled order
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
  function action(OrderType current, OrderType other, uint256 price, uint256 amount) private nonReentrant {
    require(price != 0, "IntegratedLimitOrderDEX: Price is 0");
    require(amount != 0, "IntegratedLimitOrderDEX: Amount is 0");

    PricePoint storage point = _points[price];
    // If there's counter orders at this price, fill them
    if (point.orderType == other) {
      uint256 filled = fill(current == OrderType.Buy, price, amount, point);
      // Return if fully filled
      if (filled == amount) {
        return;
      }
      amount -= filled;
    }

    // If there's nothing at this price point, naturally or due to filling orders, set it
    if (point.orderType == OrderType.Null) {
      point.orderType = current;
      if (current == OrderType.Buy) {
        emit NewBuyOrder(price);
      } else {
        emit NewSellOrder(price);
      }
    }

    // Add the new order
    // We could also merge orders here, if an existing order at this price point existed
    point.orders.push(Order(msg.sender, amount));
    emit OrderIncrease(msg.sender, price, amount);
  }

  function buy(uint256 price, uint256 amount) external override {
    require(whitelisted(msg.sender), "IntegratedLimitOrderDEX: Not whitelisted to hold this token");
    // Support fee on transfer tokens
    // Safe against re-entrancy as action has nonReentrant
    // The Crowdfund contract actually verifies its token isn't fee on transfer
    // The Thread initializer uses the same token for both that and this
    // That said, any token which can have its fee set may be set to 0 during Crowdfund,
    // allowing it to pass, yet set to non-0 later in its life, causing this to fail
    // USDT notably has fee on transfer code, currently set to 0, that may someday activate
    uint256 balance = IERC20(dexToken).balanceOf(address(this));
    IERC20(dexToken).safeTransferFrom(msg.sender, address(this), price * amount);
    action(OrderType.Buy, OrderType.Sell, price, IERC20(dexToken).balanceOf(address(this)) - balance);
  }

  function sell(uint256 price, uint256 amount) external override {
    locked[msg.sender] += amount;
    require(balanceOf(msg.sender) > locked[msg.sender], "IntegratedLimitOrderDEX: Not enough balance");
    action(OrderType.Sell, OrderType.Buy, price, amount);
  }

  function cancelOrder(uint256 price, uint256 i) external override {
    PricePoint storage point = _points[price];
    require(point.orderType != OrderType.Null, "IntegratedLimitOrderDEX: Trying to cancel a null order");
    require(point.orders[i].holder == msg.sender, "IntegratedLimitOrderDEX: Trying to cancel an point which isn't yours");

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

  function getOrderHolder(uint256 price, uint256 i) external view override returns (address) {
    return _points[price].orders[i].holder;
  }

  function getOrderAmount(uint256 price, uint256 i) external view override returns (uint256) {
    return _points[price].orders[i].amount;
  }
}
