// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

interface IIntegratedLimitOrderDEX {
  enum OrderType { Null, Buy, Sell }

  event Filled(address indexed sender, address indexed recipient, uint256 indexed price, uint256 amount);
  event NewOrder(OrderType indexed orderType, uint256 indexed price);
  event OrderIncrease(address indexed sender, uint256 indexed price, uint256 amount);

  function dexToken() external view returns (address);
  function locked(address person) external view returns (uint256);

  function buy(
    address trader,
    uint256 payment,
    uint256 price,
    uint256 minimumAmount
  ) external returns (uint256, uint256);
  function sell(uint256 price, uint256 amount) external returns (uint256, uint256);
  function cancelOrder(uint256 price, uint256 i) external;

  function getPointType(uint256 price) external view returns (uint256);
  function getOrderQuantity(uint256 price) external view returns (uint256);
  function getOrderTrader(uint256 price, uint256 i) external view returns (address);
  function getOrderAmount(uint256 price, uint256 i) external view returns (uint256);
}

error ZeroPrice();
error ZeroAmount();
error EOABuyer(address buyer);
error NotWhitelisted(address recipient, address whitelist);
error LessThanMinimumAmount(uint256 amount, uint256 minimumAmount);
error NotEnoughFunds(uint256 required, uint256 balance);
error NullOrder();
error NotOrderTrader(address caller, address trader);