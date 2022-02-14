// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IIntegratedLimitOrderDex {
  event Filled(address indexed sender, address indexed recipient, uint256 indexed price, uint256 amount);
  event NewBuyOrder(uint256 indexed price);
  event NewSellOrder(uint256 indexed price);
  event OrderIncrease(address indexed sender, uint256 indexed price, uint256 amount);

  function buy(uint256 amount, uint256 price) external payable;
  function sell(uint256 amount, uint256 price) external;
  function cancelOrder(uint256 price, uint256 i) external;
  function withdraw() external;

  function getOrderType(uint256 price) external view returns (uint256);
  function getOrderQuantity(uint256 price) external view returns (uint256);
  function getOrderHolder(uint256 price, uint256 i) external view returns (address);
  function getOrderAmount(uint256 price, uint256 i) external view returns (uint256);
  function getEthBalance(address holder) external view returns (uint256);
}
