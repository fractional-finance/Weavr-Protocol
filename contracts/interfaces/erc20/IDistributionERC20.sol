// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../common/Errors.sol";
import "../common/IComposable.sol";

interface IDistributionERC20 is IVotesUpgradeable, IERC20, IComposable {
  event NewDistribution(uint256 indexed id, address indexed token, uint112 amount);
  event Claimed(uint256 indexed id, address indexed person, uint112 amount);

  function claimed(uint256 id, address person) external view returns (bool);

  function distribute(address token, uint112 amount) external;
  function claim(uint256 id, address person) external;
}

error Delegation();
error FeeOnTransfer(address token);
error AlreadyClaimed(uint256 id, address person);
