// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface ICrowdfund {
  event CrowdfundStarted(address indexed agent, address indexed thread, address indexed token, uint256 target);
  event StateChange(uint256 indexed state, bytes data);
  event Deposit(address indexed depositor, uint256 amount);
  event Withdraw(address indexed depositor, uint256 amount);
  event Refund(address indexed depositor, uint256 refundAmount);

  function agent() external view returns (address);
  function thread() external view returns (address);

  function token() external view returns (address);
  function target() external view returns (uint256);
  function deposited() external view returns (uint256);

  function state() external view returns (uint256);
  function refunded() external view returns (uint256);

  function deposit(uint256 amount) external;
  function withdraw(uint256 amount) external;
  function cancel() external;
  function execute() external;
  function refund(uint256 amount) external;
  function claimRefund(address depositor) external;
  function finish() external;
  function burn(address person, uint256 amount) external;
}
