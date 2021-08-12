// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/asset/IIntegratedLimitOrderDex.sol";

// In order to be integrated into an ERC20, the ERC20 must allow itself to transfer from any holder
abstract contract IntegratedLimitOrderDex is IIntegratedLimitOrderDex {
  using SafeERC20 for IERC20;

  enum OrderType { Null, Buy, Sell }
  struct Suborder {
    address holder;
    uint256 amount;
  }

  struct Order {
    OrderType orderType;
    Suborder[] holders;
  }

  // Indexed by price
  mapping (uint256 => Order) private _orders;

  // ETH balances
  // Used when an order is filled as ETH cannot be directly transferred
  // While it technically can be, it risks causing the transaction to fail
  mapping (address => uint256) private _eth;

  // Fill an order
  function fill(bool buying, uint256 amount, uint256 price, Order storage order) private returns (uint256) {
    // Fill orders until there are either no orders or our order is filled
    uint256 filled = 0;
    uint256 h = 0;
    for (; (h < order.holders.length) && (amount != filled); h++) {
      uint256 thisAmount = order.holders[h].amount;
      if (thisAmount > amount) {
        thisAmount = amount;
      }
      order.holders[h].amount -= thisAmount;
      filled += thisAmount;
      emit Filled(msg.sender, order.holders[h].holder, price, amount);

      if (buying) {
        // Internally transfer ETH
        // We can't directly transfer ETH due to the ability for any recipient of ETH to cause the transaction to fail
        _eth[order.holders[h].holder] += thisAmount * price;
      } else {
        // Internally transfer the sold ERC20s
        // Uses an external call in order to set msg.sender to address(this)
        IERC20(address(this)).safeTransfer(order.holders[h].holder, thisAmount);
      }
    }

    // Transfer the purchased ERC20 sum
    if (buying) {
      IERC20(address(this)).safeTransfer(msg.sender, filled);
    } else {
      _eth[msg.sender] += filled * price;
    }

    // h will always be after the last edited order
    h--;

    // This crux order may have been partially filled or fully filled
    // If it's partially filled, decrement again
    if (order.holders[h].amount != 0) {
      // Prevents reversion by underflow
      // If we didn't fill any orders, there's nothing left to do
      if (h == 0) {
        return filled;
      }
      h--;
    }

    // If we filled every order, set the order type to null
    if (h == (order.holders.length - 1)) {
      order.orderType = OrderType.Null;
      // Clear the holders array
      // For now, this also offers a gas refund, yet future EIPs will remove this
      while (order.holders.length != 0) {
        order.holders.pop();
      }
    } else {
      // Do a O(1) deletion from the holders array for each filled order
      // A shift would be very expensive and the 18 decimal accuracy of Ethereum means preserving the order of orders wouldn't be helpful
      // 1 wei is microscopic, so placing a 1 wei different order...
      for (uint256 i = 0; i <= h; i++) {
        if ((h + i) < order.holders.length) {
          order.holders[i] = order.holders[order.holders.length - 1];
        }
        order.holders.pop();
      }
    }

    return filled;
  }

  // Price is always denoted in ETH
  function buy(uint256 amount, uint256 price) public override payable {
    require(amount != 0, "IntegratedLimitOrderDex: Amount is 0");
    require(price != 0, "IntegratedLimitOrderDex: Price is 0");
    require(msg.value == amount * price, "IntegratedLimitOrderDex: Invalid message value");

    Order storage order = _orders[price];
    if (order.orderType == OrderType.Null) {
      order.orderType = OrderType.Buy;
      order.holders.push(Suborder(msg.sender, amount));
      emit NewBuyOrder(price);
      emit OrderIncrease(msg.sender, price, amount);
    } else if (order.orderType == OrderType.Buy) {
      order.holders.push(Suborder(msg.sender, amount));
      emit OrderIncrease(msg.sender, price, amount);
    } else if (order.orderType == OrderType.Sell) {
      uint256 filled = fill(true, amount, price, order);

      // Create a buy order for any outstanding amount
      if (filled < amount) {
        order.orderType = OrderType.Buy;
        order.holders.push(Suborder(msg.sender, amount - filled));
        emit NewBuyOrder(price);
        emit OrderIncrease(msg.sender, price, amount);
      }
    } else {
      require(false, "IntegratedLimitOrderDex: OrderType enum expanded yet not case handler");
    }
  }

  function sell(uint256 amount, uint256 price) public override {
    require(amount != 0, "IntegratedLimitOrderDex: Amount is 0");
    require(price != 0, "IntegratedLimitOrderDex: Price is 0");
    IERC20(address(this)).safeTransferFrom(msg.sender, address(this), amount);

    Order storage order = _orders[price];
    if (order.orderType == OrderType.Null) {
      order.orderType = OrderType.Sell;
      order.holders.push(Suborder(msg.sender, amount));
      emit NewSellOrder(price);
      emit OrderIncrease(msg.sender, price, amount);
    } else if (order.orderType == OrderType.Buy) {
      uint256 filled = fill(false, amount, price, order);
      if (filled < amount) {
        order.orderType = OrderType.Sell;
        order.holders.push(Suborder(msg.sender, amount - filled));
        emit NewSellOrder(price);
        emit OrderIncrease(msg.sender, price, amount - filled);
      }
    } else if (order.orderType == OrderType.Sell) {
      order.holders.push(Suborder(msg.sender, amount));
    } else {
      require(false, "IntegratedLimitOrderDex: OrderType enum expanded yet not case handler");
    }
  }

  function cancelOrder(uint256 price, uint256 i) external override {
    require(_orders[price].orderType != OrderType.Null, "IntegratedLimitOrderDex: Trying to cancel a null order");
    require(_orders[price].holders[i].holder == msg.sender, "IntegratedLimitOrderDex: Trying to cancel an order which isn't yours");

    if (_orders[price].orderType == OrderType.Buy) {
      // It may be better to have this add to _eth, pushing its flow through withdraw
      (bool success, ) = msg.sender.call{value: (_orders[price].holders[i].amount * price)}("");
      require(success, "IntegratedLimitOrderDex: Couldn't transfer the ETH back to the order placer");
    } else if (_orders[price].orderType == OrderType.Sell) {
      IERC20(address(this)).safeTransfer(msg.sender, _orders[price].holders[i].amount);
    } else {
      require(false, "IntegratedLimitOrderDex: OrderType enum expanded yet not case handler");
    }

    // If this is not the last order, shift the last order down
    if (i != (_orders[price].holders.length - 1)) {
      _orders[price].holders[i] = _orders[price].holders[_orders[price].holders.length - 1];
    }
    _orders[price].holders.pop();
  }

  function withdraw() public override {
    uint256 balance = _eth[msg.sender];
    _eth[msg.sender] = 0;
    (bool success, ) = msg.sender.call{value: balance}("");
    require(success, "IntegratedLimitOrderDex: Couldn't withdraw ETH");
  }

  function getOrderType(uint256 price) public view override returns (uint256) {
    return uint256(_orders[price].orderType);
  }

  function getOrderQuantity(uint256 price) public view override returns (uint256) {
    return _orders[price].holders.length;
  }

  function getOrderHolder(uint256 price, uint256 i) public view override returns (address) {
    return _orders[price].holders[i].holder;
  }

  function getOrderAmount(uint256 price, uint256 i) public view override returns (uint256) {
    return _orders[price].holders[i].amount;
  }

  function getEthBalance(address holder) public view override returns (uint256) {
    return _eth[holder];
  }
}
