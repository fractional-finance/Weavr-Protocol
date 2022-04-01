// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/ITimelock.sol";

// Just as the Thread can upgrade to claw back tokens, the Frabric could theoretically
// upgrade the ThreadDeployer to void its timelock. This non-upgradeable contract
// enforces it
contract Timelock is Ownable, Composable, ITimelockSum {
  using SafeERC20 for IERC20;

  struct LockStruct {
    uint256 time;
    uint256 months;
  }
  mapping(address => LockStruct) internal _locks;

  constructor() Ownable() {
    __Composable_init();
    contractName = keccak256("Timelock");
    version = type(uint256).max;
    supportsInterface[type(Ownable).interfaceId] = true;
    supportsInterface[type(ITimelock).interfaceId] = true;
  }

  function lock(address token, uint256 months) external override onlyOwner {
    LockStruct storage _lock = _locks[token];

    // Would trivially be a DoS if token addresses were known in advance and this wasn't onlyOwner
    if (_lock.months != 0) {
      revert AlreadyLocked(token);
    }

    _lock.time = block.timestamp + (30 days);
    _lock.months = months;
    emit Lock(token, months);
  }

  function claim(address token) external override {
    LockStruct storage _lock = _locks[token];
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
    IERC20(token).safeTransfer(owner(), amount);
    emit Claim(token, amount);
  }

  function getLockNextTime(address token) external view override returns (uint256) {
    return _locks[token].time;
  }
  function getLockRemainingMonths(address token) external view override returns (uint256) {
    return _locks[token].months;
  }
}
