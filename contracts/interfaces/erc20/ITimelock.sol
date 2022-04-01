// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface ITimelock {
  event Lock(address indexed token, uint256 indexed months);
  event Claim(address indexed token, uint256 amount);

  function lock(address token, uint256 months) external;
  function claim(address token) external;

  function getLockNextTime(address token) external view returns (uint256);
  function getLockRemainingMonths(address token) external view returns (uint256);
}

interface ITimelockSum is IComposableSum, ITimelock {}

error AlreadyLocked(address token);
error Locked(address token, uint256 time, uint256 nextTime);
