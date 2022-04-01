// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../common/IComposable.sol";

interface IDividendERC20 {
  event Distributed(address indexed token, uint256 amount);
  event Claimed(address indexed person, uint256 indexed id, uint256 amount);

  function claimedDistribution(address person, uint256 id) external view returns (bool);

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}

interface IDividendERC20Sum is IVotesUpgradeable, IERC20, IComposableSum, IDividendERC20 {}

error Delegation();
error AlreadyClaimed(uint256 id);
