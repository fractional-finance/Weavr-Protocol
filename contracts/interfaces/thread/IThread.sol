// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IDAO.sol";

interface IThread is IDAO {
  event OracleChangeProposed(uint256 indexed id, address indexed oracle);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);
  event PaperDecision(uint256 indexed id);
  event OracleChanged(address indexed oldOracle, address indexed newOracle);
  event Dissolved(uint256 indexed id);

  function oracle() external view returns (address);
  function crowdfund() external view returns (address);

  function initialize(
    address _crowdfund,
    address _erc20,
    string memory name,
    string memory symbol,
    address parentWhitelist,
    address agent,
    address raiseToken,
    uint256 target
  ) external;

  function migrateFromCrowdfund() external;

  function proposePaper(string calldata info) external returns (uint256 id);
  function proposeOracleChange(
    string calldata info,
    address _oracle
  ) external returns (uint256 id);
  function proposeDissolution(
    string calldata info,
    address purchaser,
    address token,
    uint256 purchaseAmount
  ) external returns (uint256 id);
}
