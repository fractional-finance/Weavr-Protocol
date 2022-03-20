// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable as IVotes } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../lists/IFrabricWhitelist.sol";
import "./IIntegratedLimitOrderDEX.sol";

// Doesn't include Ownable, IERC20, and IVotes due to linearization issues by solc
interface IFrabricERC20 is IFrabricWhitelist, IIntegratedLimitOrderDEX {
  event Distributed(address indexed token, uint256 amount);
  event Claimed(address indexed person, uint256 indexed id, uint256 amount);

  function mintable() external view returns (bool);
  function claimedDistribution(address person, uint256 id) external view returns (bool);

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool mintable,
    address parentWhitelist,
    address dexToken
  ) external;

  function mint(address to, uint256 amount) external;

  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;

  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}
