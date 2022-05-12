// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IThread is IFrabricDAO {
  event DescriptorChangeProposal(uint256 id, bytes32 indexed descriptor);
  event FrabricChangeProposal(uint256 indexed id, address indexed frabric, address indexed governor);
  event GovernorChangeProposal(uint256 indexed id, address indexed governor);
  event EcosystemLeaveWithUpgradesProposal(uint256 indexed id, address indexed frabric, address indexed governor);
  event DissolutionProposal(uint256 indexed id, address indexed token, uint256 price);

  event DescriptorChange(bytes32 indexed oldDescriptor, bytes32 indexed newDescriptor);
  event FrabricChange(address indexed oldFrabric, address indexed newFrabric);
  event GovernorChange(address indexed oldGovernor, address indexed newGovernor);

  enum ThreadProposalType {
    DescriptorChange,
    FrabricChange,
    GovernorChange,
    EcosystemLeaveWithUpgrades,
    Dissolution
  }

  function upgradesEnabled() external view returns (uint256);
  function descriptor() external view returns (bytes32);
  function governor() external view returns (address);
  function frabric() external view returns (address);
  function irremovable(address participant) external view returns (bool);

  function proposeDescriptorChange(
    bytes32 _descriptor,
    bytes32 info
  ) external returns (uint256);
  function proposeFrabricChange(
    address _frabric,
    address _governor,
    bytes32 info
  ) external returns (uint256);
  function proposeGovernorChange(
    address _governor,
    bytes32 info
  ) external returns (uint256);
  function proposeEcosystemLeaveWithUpgrades(
    address newFrabric,
    address newGovernor,
    bytes32 info
  ) external returns (uint256);
  function proposeDissolution(
    address token,
    uint112 price,
    bytes32 info
  ) external returns (uint256);
}

interface IThreadInitializable is IThread {
  function initialize(
    string memory name,
    address erc20,
    bytes32 descriptor,
    address frabric,
    address governor,
    address[] calldata irremovable
  ) external;
}

error NotGovernor(address caller, address governor);
error ProposingUpgrade(address beacon, address instance, address code);
error Irremovable(address participant);
error NotLeaving(address frabric, address newFrabric);
