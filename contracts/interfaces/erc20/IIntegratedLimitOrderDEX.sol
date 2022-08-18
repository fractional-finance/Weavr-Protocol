// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import {errors} from "../common/Errors.sol";
import "../common/IComposable.sol";

interface IIntegratedLimitOrderDEXCore {
  enum OrderType { Null, Buy, Sell }

  event Order(OrderType indexed orderType, uint256 indexed price);
  event OrderIncrease(address indexed trader, uint256 indexed price, uint256 amount);
  event OrderFill(address indexed orderer, uint256 indexed price, address indexed executor, uint256 amount);
  event OrderCancelling(address indexed trader, uint256 indexed price);
  event OrderCancellation(address indexed trader, uint256 indexed price, uint256 amount);

  // Part of core to symbolize amount should always be whole while price is atomic
  function atomic(uint256 amount) external view returns (uint256);

  function tradeToken() external view returns (address);

  // sell is here as the FrabricDAO has the ability to sell tokens on their integrated DEX
  // That means this function API can't change (along with cancelOrder which FrabricDAO also uses)
  // buy is meant to be used by users, offering greater flexibility, especially as it has a router for a frontend
  function sell(uint256 price, uint256 amount) external returns (uint256);
  function cancelOrder(uint256 price, uint256 i) external returns (bool);
}

interface IIntegratedLimitOrderDEX is IComposable, IIntegratedLimitOrderDEXCore {
  function tradeTokenBalance() external view returns (uint256);
  function tradeTokenBalances(address trader) external view returns (uint256);
  function locked(address trader) external view returns (uint256);

  function withdrawTradeToken(address trader) external;

  function buy(
    address trader,
    uint256 price,
    uint256 minimumAmount
  ) external returns (uint256);

  function pointType(uint256 price) external view returns (IIntegratedLimitOrderDEXCore.OrderType);
  function orderQuantity(uint256 price) external view returns (uint256);
  function orderTrader(uint256 price, uint256 i) external view returns (address);
  function orderAmount(uint256 price, uint256 i) external view returns (uint256);
}

error LessThanMinimumAmount(uint256 amount, uint256 minimumAmount);
error NotEnoughFunds(uint256 required, uint256 balance);
error NotOrderTrader(address caller, address trader);
