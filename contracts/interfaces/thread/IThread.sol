// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IDAO.sol";

interface IThread is IDAO {
  event PaperProposed(uint256 indexed id, string info);
  event AgentChangeProposed(uint256 indexed id, address indexed agent);
  event FrabricChangeProposed(uint256 indexed id, address indexed frabric);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);

  event PaperDecision(uint256 indexed id);
  event AgentChanged(address indexed oldAgent, address indexed newAgent);
  event FrabricChanged(address indexed oldAgent, address indexed newAgent);
  event Dissolved(uint256 indexed id);

  function crowdfund() external view returns (address);
  function agent() external view returns (address);
  function frabric() external view returns (address);

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
  function proposeAgentChange(
    string calldata info,
    address _agent
  ) external returns (uint256 id);
  function proposeFrabricChange(
    string calldata info,
    address _frabric
  ) external returns (uint256 id);
  function proposeDissolution(
    string calldata info,
    address token,
    uint256 purchaseAmount
  ) external returns (uint256 id);
}
