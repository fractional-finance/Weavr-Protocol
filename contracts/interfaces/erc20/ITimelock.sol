// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface ITimelock is IComposable {
  event Lock(address indexed token, uint8 indexed months);
  event Claim(address indexed token, uint256 amount);

  function lock(address token, uint8 months) external;
  function claim(address token) external;

  function getLockNextTime(address token) external view returns (uint64);
  function getLockRemainingMonths(address token) external view returns (uint8);
}

error AlreadyLocked(address token);
error Locked(address token, uint256 time, uint256 nextTime);
