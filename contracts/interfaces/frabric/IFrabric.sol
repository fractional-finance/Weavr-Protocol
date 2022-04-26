// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IUpgradeable.sol";
import "../dao/IFrabricDAO.sol";

interface IFrabricCore is IFrabricDAO {
  enum GovernorStatus {
    Null,
    Unverified, // Proposed and elected, yet hasn't gone through KYC
    Active,
    // Removed is last as GovernorStatus is written as a linear series of transitions
    // > Unverified will work to find any Governor which was ever active
    Removed
  }

  function governor(address governor) external view returns (GovernorStatus);
}

interface IFrabric is IFrabricCore {
  enum FrabricProposalType {
    Participants,
    RemoveBond,
    Thread,
    ThreadProposal
  }

  enum ParticipantType {
    Null,
    // Removed is before any other type to allow using > Removed to check validity
    Removed,
    Genesis,
    KYC,
    Governor,
    Individual,
    Corporation
  }

  event ParticipantsProposal(
    uint256 indexed id,
    ParticipantType indexed participantType,
    bytes32 participants
  );
  event BondRemovalProposal(
    uint256 indexed id,
    address indexed participant,
    bool indexed slash,
    uint256 amount
  );
  event ThreadProposal(
    uint256 indexed id,
    uint256 indexed variant,
    address indexed governor,
    string name,
    string symbol,
    bytes32 descriptor,
    bytes data
  );
  event ThreadProposalProposal(
    uint256 indexed id,
    address indexed thread,
    uint256 indexed proposalType,
    bytes32 info
  );
  event ParticipantChange(address indexed participant, ParticipantType indexed participantType);

  function participant(address participant) external view returns (ParticipantType);

  function bond() external view returns (address);
  function threadDeployer() external view returns (address);

  function proposeParticipants(
    ParticipantType participantType,
    bytes32 participants,
    bytes32 info
  ) external returns (uint256);
  function proposeBondRemoval(
    address governor,
    bool slash,
    uint256 amount,
    bytes32 info
  ) external returns (uint256);
  function proposeThread(
    uint8 variant,
    string calldata name,
    string calldata symbol,
    bytes32 descriptor,
    address governor,
    bytes calldata data,
    bytes32 info
  ) external returns (uint256);
  function proposeThreadProposal(
    address thread,
    uint16 proposalType,
    bytes calldata data,
    bytes32 info
  ) external returns (uint256);

  function approve(
    uint256 id,
    address approving,
    bytes32 kycHash,
    bytes32[] memory proof,
    bytes calldata signature
  ) external;
}

interface IFrabricUpgradeable is IFrabric, IUpgradeable {}

error InsecureUpgradeFunction();

error ProposingNullParticipants();
error ProposingGenesisParticipants();
error InvalidAddress(bytes32 invalid);
error ParticipantAlreadyApproved(address participant);
error InvalidName(string name, string symbol);
error ProposingParticipantRemovalOnThread();
error ProposingFrabricChange();
error ExternalCallFailed(address called, bytes4 selector, bytes error);
error ParticipantsProposalNotPassed(uint256 id);
error InvalidKYCSignature(address signer, IFrabric.ParticipantType status);
error IncorrectParticipant(address participant, bytes32 participants, bytes32[] proof);
