// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IThread is IFrabricDAO {
  event DescriptorChangeProposed(uint256 id, bytes32 indexed descriptor);
  event AgentChangeProposed(uint256 indexed id, address indexed agent);
  event FrabricChangeProposed(uint256 indexed id, address indexed frabric);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);

  event DescriptorChanged(bytes32 indexed oldDescriptor, bytes32 indexed newDescriptor);
  event AgentChanged(address indexed oldAgent, address indexed newAgent);
  event FrabricChanged(address indexed oldAgent, address indexed newAgent);
  event Dissolved(uint256 indexed id);

  enum ThreadProposalType {
    EnableUpgrades,
    DescriptorChange,
    AgentChange,
    FrabricChange,
    Dissolution
  }

  function upgradesEnabled() external view returns (uint256);
  function descriptor() external view returns (bytes32);
  function agent() external view returns (address);
  function frabric() external view returns (address);

  function proposeEnablingUpgrades(bytes32 info) external returns (uint256);
  function proposeDescriptorChange(
    bytes32 _descriptor,
    bytes32 info
  ) external returns (uint256);
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
    bytes32 descriptor,
    address frabric,
    address agent
  ) external;
}

error NotAgent(address caller, address agent);
