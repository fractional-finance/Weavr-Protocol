// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/thread/IThread.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/ITimelock.sol";

// Just as the Thread can upgrade to claw back tokens, the Frabric could theoretically
// upgrade the ThreadDeployer to void its timelock. This non-upgradeable contract
// enforces it
contract Timelock is Ownable, Composable, ITimelock {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  struct LockStruct {
    uint64 time;
    uint8 months;
  }
  mapping(address => LockStruct) private _locks;

  constructor() Composable("Timelock") Ownable() initializer {
    __Composable_init("Timelock", true);
    supportsInterface[type(Ownable).interfaceId] = true;
    supportsInterface[type(ITimelock).interfaceId] = true;
  }

  function lock(address token, uint8 months) external override onlyOwner {
    LockStruct storage _lock = _locks[token];

    // Would trivially be a DoS if token addresses were known in advance and this wasn't onlyOwner
    if (_lock.months != 0) {
      revert AlreadyLocked(token);
    }

    _lock.time = uint64(block.timestamp) + (30 days);
    _lock.months = months;
    emit Lock(token, months);
  }

  function claim(address token) external override {
    LockStruct storage _lock = _locks[token];

    // If this is a Thread token, and they've enabled upgrades, void the timelock
    // Prevents an attack vector documented in Thread where Threads can upgrade to claw back timelocked tokens
    // Enabling upgrades takes longer than voiding the timelock and actioning the tokens to some effect in response
    if (
      // OZ code will return false if this call errors, though some fallback functions may be misinterpreted
      // If fallback functions return a false value, this won't execute and it's a non-issue
      // If it returns a true value, and does for the next call as well, it'll clear the lock months which isn't an issue
      // The only reason non-Thread tokens should be here is on accident which means we're performing recovery
      // If for some reason this returns true, and the next call errors, that's some weird edge case
      // with an unsupported token which shouldn't be here and that's that
      (token.supportsInterface(type(IThread).interfaceId)) &&
      (IThread(token).upgradesEnabled() != 0)
    ) {
      _lock.months = 0;
    }

    // Enables recovering accidentally sent tokens
    if (_lock.months == 0) {
      _lock.months = 1;
    } else {
      if (_lock.time > block.timestamp) {
        revert Locked(token, block.timestamp, _lock.time);
      }
      _lock.time += 30 days;
    }

    uint256 amount = IERC20(token).balanceOf(address(this)) / _lock.months;
    _lock.months -= 1;
    emit Claim(token, amount);
    IERC20(token).safeTransfer(owner(), amount);
  }

  function getLockNextTime(address token) external view override returns (uint64) {
    return _locks[token].time;
  }
  function getLockRemainingMonths(address token) external view override returns (uint8) {
    return _locks[token].months;
  }
}
