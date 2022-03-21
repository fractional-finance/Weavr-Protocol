// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "../dao/IFrabricDAO.sol";

interface IThread is IFrabricDAO {
  event AgentChangeProposed(uint256 indexed id, address indexed agent);
  event FrabricChangeProposed(uint256 indexed id, address indexed frabric);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);

  event AgentChanged(address indexed oldAgent, address indexed newAgent);
  event FrabricChanged(address indexed oldAgent, address indexed newAgent);
  event Dissolved(uint256 indexed id);

  enum ThreadProposalType {
    AgentChange,
    FrabricChange,
    Dissolution
  }

  function agent() external view returns (address);
  function frabric() external view returns (address);

  function initialize(
    address _erc20,
    address _agent,
    address _frabric
  ) external;

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
