// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../dao/IDao.sol";
import "./IAssetERC20.sol";

interface IAsset is IDao, IAssetERC20 {
  event ProposedPlatformChange(uint256 indexed id, address indexed platform);
  event ProposedOracleChange(uint256 indexed id, address indexed oracle);
  event ProposedDissolution(uint256 indexed id, address indexed purchaser, address token, uint256 purchaseAmount);
  event PlatformChanged(uint256 indexed id, address indexed platform);
  event OracleChanged(uint256 indexed id, address indexed oldOracle, address indexed newOracle);
  event Dissolved(uint256 indexed id, address indexed purchaser, uint256 purchaseAmount);

  function oracle() external returns (address);
  function votes() external returns (uint256);
  function proposalVoteHeight(uint256 id) external view returns (uint256);

  function proposePaper(string calldata info) external returns (uint256);
  function proposePlatformChange(string calldata info, address platform, uint256 newNFT) external returns (uint256);
  function proposeOracleChange(string calldata info, address newOracle) external returns (uint256);
  function proposeDissolution(string calldata info, address purchaser, address token, uint256 purchaseAmount) external returns (uint256);

  function voteYes(uint256 id) external;
  function voteNo(uint256 id) external;
  function abstain(uint256 id) external;

  function passProposal(uint256 id) external;
  function cancelProposal(uint256 id, address[] calldata rengers) external;
  function enactProposal(uint256 id) external;

  function reclaimDissolutionFunds(uint256 id) external;
}
