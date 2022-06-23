// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

// Imports the ILO DEX interface due to shared errors
import "../erc20/IIntegratedLimitOrderDEX.sol";

import "../erc20/IDistributionERC20.sol";

interface ICrowdfund is IDistributionERC20 {
  enum State {
    Active,
    Executing,
    Refunding,
    Finished
  }

  event StateChange(State indexed state);
  event Deposit(address indexed depositor, uint112 amount);
  event Withdraw(address indexed depositor, uint112 amount);
  event Refund(address indexed depositor, uint112 refundAmount);

  function whitelist() external view returns (address);

  function governor() external view returns (address);
  function thread() external view returns (address);

  function token() external view returns (address);
  function target() external view returns (uint112);
  function outstanding() external view returns (uint112);
  function lastDepositTime() external view returns (uint64);

  function state() external view returns (State);

  function normalizeRaiseToThread(uint256 amount) external returns (uint256);

  function deposit(uint112 amount) external returns (uint112);
  function withdraw(uint112 amount) external;
  function cancel() external;
  function execute() external;
  function refund(uint112 amount) external;
  function finish() external;
  function redeem(address depositor) external;
}

interface ICrowdfundInitializable is ICrowdfund {
  function initialize(
    string memory name,
    string memory symbol,
    address _whitelist,
    address _governor,
    address _thread,
    address _token,
    uint112 _target
  ) external;
}

error CrowdfundTransfer();
error InvalidState(ICrowdfund.State current, ICrowdfund.State expected);
error CrowdfundReached();
error CrowdfundNotReached();
