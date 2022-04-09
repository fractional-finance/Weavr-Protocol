// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IThread is IFrabricDAO {
  event AgentChangeProposed(uint256 indexed id, address indexed agent);
  event FrabricChangeProposed(uint256 indexed id, address indexed frabric);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);

  event AgentChanged(address indexed oldAgent, address indexed newAgent);
  event FrabricChanged(address indexed oldAgent, address indexed newAgent);
  event Dissolved(uint256 indexed id);

  enum ThreadProposalType {
    EnableUpgrades,
    AgentChange,
    FrabricChange,
    Dissolution
  }

  function agent() external view returns (address);
  function frabric() external view returns (address);
  function upgradesEnabled() external view returns (uint256);

  function proposeEnablingUpgrades(bytes32 info) external returns (uint256);
  function proposeAgentChange(
    address _agent,
    bytes32 info
  ) external returns (uint256);
  function proposeFrabricChange(
    address _frabric,
    bytes32 info
  ) external returns (uint256);
  function proposeDissolution(
    address token,
    uint256 purchaseAmount,
    bytes32 info
  ) external returns (uint256);
}

interface IThreadInitializable is IThread {
  function initialize(
    string memory name,
    address erc20,
    address agent,
    address frabric
  ) external;
}

error NotAgent(address caller, address agent);
