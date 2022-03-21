// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";
import "../interfaces/erc20/IDEXRouter.sol";

// The IntegratedLimitOrderDEX has an issue where it can be upgraded with the FrabricERC20 by a Thread
// This is completely intended behavior
// The issue is that the UX is expected to offer infinite approvals on each DEX to reduce the number of transactions required
// If a single Thread goes rogue under this system, it can have the DEX drain user wallets via these approvals
// To solve this, this DEX router exists. Users approve the DEX router to spend their non-Thread tokens
// Since this isn't deployed by a proxy, no party can upgrade it to drain wallets
// Thread tokens are still directly traded via communicating with the Thread contract
// Order cancellations are still handled via communicating with the Thread contract
// The Thread can still upgrade to abscond with all coins held in open orders

// A global DEX not built into each Thread's ERC20 would also make sense,
// especially since there's now this global contract, except slash mechanics
// are most effective when the DEX is built into the ERC20 controlled by the Thread
// While Uniswap will be whitelisted, it can't be used to effectively hold tokens,
// only to sell them or provide liquidity (a form of holding yet one requiring equal
// capital lockup while providing a service others can take advantage of)

contract DEXRouter is IDEXRouter {
  using SafeERC20 for IERC20;

  mapping(address => bool) internal _approved;

  function buy(address token, uint256 payment, uint256 price, uint256 minimumAmount) external {
    IERC20 dexToken = IERC20(IIntegratedLimitOrderDEX(token).dexToken());

    // Transfer only the needed amount of capital
    dexToken.safeTransferFrom(msg.sender, address(this), payment);

    // Gas optimization by not constantly calling approve if we already did
    if (!_approved[token]) {
      dexToken.approve(token, type(uint256).max);
      _approved[token] = true;
    }

    // Place an order with the exact amount received, leaving this contract with 0 funds
    IIntegratedLimitOrderDEX(token).buy(msg.sender, dexToken.balanceOf(address(this)), price, minimumAmount);
  }

  // Technically, the uint256 max may be completely moved through here in volume
  // While OZ ERC20s won't decrease the allowance if it's uint256 max, this isn't ERC20-spec behavior
  // This allows a Thread ERC20 to reset its allowance in case it does ever run out
  function refreshAllowance(address token) external {
    IERC20(IIntegratedLimitOrderDEX(token).dexToken()).approve(token, type(uint256).max);
    // Set _approved in case it wasn't already
    // While this should never be called before buy is called, so this should always be set
    // And even if it wasn't, it wouldn't be an issue, this should never be called
    // It's at least extremely unlikely to be called, whereas buy is extremely likely
    // That's why it makes sense to put these gas costs here
    _approved[token] = true;
  }

  // Doesn't have a fund recover function as anyone can claim a Thread 'exists' to drain this contract of funds in it
  // This contract should never hold funds yet we can't stop people from accidentally sending here
  // A recover function would be nice accordingly, yet one already does exist thanks to the above
  // To make it secure would require knowing legitimate vs illegitimate Threads,
  // which would lock this router to a specific Frabric, stopping offshoots
  // That is not acceptable behavior
}
