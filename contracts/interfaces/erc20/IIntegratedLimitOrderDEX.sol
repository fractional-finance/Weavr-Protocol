// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IIntegratedLimitOrderDEX {
  event Filled(address indexed sender, address indexed recipient, uint256 indexed price, uint256 amount);
  event NewBuyOrder(uint256 indexed price);
  event NewSellOrder(uint256 indexed price);
  event OrderIncrease(address indexed sender, uint256 indexed price, uint256 amount);

  function dexToken() external view returns (address);
  function locked(address person) external view returns (uint256);

  function buy(uint256 price, uint256 amount) external;
  function sell(uint256 price, uint256 amount) external;
  function cancelOrder(uint256 price, uint256 i) external;

  function getPointType(uint256 price) external view returns (uint256);
  function getOrderQuantity(uint256 price) external view returns (uint256);
  function getOrderHolder(uint256 price, uint256 i) external view returns (address);
  function getOrderAmount(uint256 price, uint256 i) external view returns (uint256);
}
