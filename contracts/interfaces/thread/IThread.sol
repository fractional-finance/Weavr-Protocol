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
    address _agent,
    string calldata info
  ) external returns (uint256 id);
  function proposeFrabricChange(
    address _frabric,
    string calldata info
  ) external returns (uint256 id);
  function proposeDissolution(
    address token,
    uint256 purchaseAmount,
    string calldata info
  ) external returns (uint256 id);
}
