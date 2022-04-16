// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IThread is IFrabricDAO {
  event DescriptorChangeProposed(uint256 id, bytes32 indexed descriptor);
  event FrabricChangeProposed(uint256 indexed id, address indexed frabric, address indexed governor);
  event GovernorChangeProposed(uint256 indexed id, address indexed governor);
  event EcosystemLeaveWithUpgradesProposed(uint256 indexed id, address indexed frabric, address indexed governor);
  event DissolutionProposed(uint256 indexed id, address indexed purchaser, address indexed token, uint256 amount);

  event DescriptorChanged(bytes32 indexed oldDescriptor, bytes32 indexed newDescriptor);
  event FrabricChanged(address indexed oldGovernor, address indexed newGovernor);
  event GovernorChanged(address indexed oldGovernor, address indexed newGovernor);
  // Includes IDs to point to the original proposals since these have nothing worth putting in them
  // They emit other events as relevant
  event LeftEcosystemWithUpgrades(uint256 indexed id);
  event Dissolved(uint256 indexed id);

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
    address governor,
    address[] calldata irremovable
  ) external;
}

error NotGovernor(address caller, address governor);
error NotLeaving(address frabric, address newFrabric);
