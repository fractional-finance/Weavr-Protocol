// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface ITimelock is IComposable {
  event Lock(address indexed token, uint8 indexed months, address recipient);
  event Claim(address indexed token, uint256 amount, address recipient);

  function lock(address token, uint8 months, address recipient) external;
  function claim(address token, address recipient) external;

  function nextLockTime(address token, address recipient) external view returns (uint64);
  function remainingMonths(address token, address recipient) external view returns (uint8);
}

error AlreadyLocked(address token, address recipient);
error Locked(address token, uint256 time, uint256 nextTime, address recipient);
