// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../common/Errors.sol";
import "../common/IComposable.sol";

interface IDistributionERC20 is IVotesUpgradeable, IERC20, IComposable {
  event Distributed(uint256 indexed id, address indexed token, uint256 amount);
  event Claimed(uint256 indexed id, address indexed person, uint256 amount);

  function claimedDistribution(address person, uint256 id) external view returns (bool);

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}

error Delegation();
error FeeOnTransfer(address token);
error AlreadyClaimed(uint256 id);
