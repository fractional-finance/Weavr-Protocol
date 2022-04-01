// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";

import "../common/Composable.sol";

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

contract DEXRouter is Composable, IDEXRouterSum {
  using SafeERC20 for IERC20;

  mapping(address => bool) internal _approved;

  constructor() {
    __Composable_init();
    contractName = keccak256("DEXRouter");
    version = type(uint256).max;
    supportsInterface[type(IDEXRouter).interfaceId] = true;
  }

  function buy(address token, uint256 payment, uint256 price, uint256 minimumAmount) external {
    IERC20 dexToken = IERC20(IIntegratedLimitOrderDEX(token).dexToken());

    // Transfer only the specified of capital
    dexToken.safeTransferFrom(msg.sender, token, payment);
    IIntegratedLimitOrderDEX(token).buy(msg.sender, price, minimumAmount);
  }

  // Doesn't have a fund recover function as this should never hold funds
  // Any recovery function would be a MEV pit unless a specific address received the funds
  // That would acknowledge a Frabric which is not the intent nor role of this contract
}
