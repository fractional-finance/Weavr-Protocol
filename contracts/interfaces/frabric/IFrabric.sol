// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "../dao/IFrabricDAO.sol";

interface IFrabric {
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

  enum GovernorStatus {
    Null,
    Unverified, // Proposed and elected, yet hasn't gone through KYC
    Active,
    // Removed is last as GovernorStatus is written as a linear series of transitions
    // > Unverified will work to find any Governor which was ever active
    Removed
  }

  event ParticipantsProposed(
    uint256 indexed id,
    ParticipantType indexed participantType,
    bytes32 participants
  );
  event RemoveBondProposed(
    uint256 indexed id,
    address indexed participant,
    bool indexed slash,
    uint256 amount
  );
  event ThreadProposed(
    uint256 indexed id,
    uint256 indexed variant,
    address indexed agent,
    string name,
    string symbol,
    bytes data
  );
  event ThreadProposalProposed(
    uint256 indexed id,
    address indexed thread,
    uint256 indexed proposalType,
    string info
  );

  event KYCChanged(address indexed oldKYC, address indexed newKYC);

  function participant(address participant) external view returns (ParticipantType);

  function bond() external view returns (address);
  function threadDeployer() external view returns (address);
  function kyc() external view returns (address);

  function governor(address governor) external view returns (GovernorStatus);

  function proposeParticipants(
    ParticipantType participantType,
    bytes32 participants,
    string calldata info
  ) external returns (uint256);
  function proposeRemoveBond(
    address governor,
    bool slash,
    uint256 amount,
    string calldata info
  ) external returns (uint256);
  function proposeThread(
    uint256 variant,
    address agent,
    string calldata name,
    string calldata symbol,
    bytes calldata data,
    string calldata info
  ) external returns (uint256);
  function proposeThreadProposal(
    address thread,
    uint256 proposalType,
    bytes calldata data,
    string calldata info
  ) external returns (uint256);

  function approve(
    uint256 id,
    address approving,
    bytes32 kycHash,
    bytes32[] memory proof,
    bytes calldata signature
  ) external;
}

interface IFrabricSum is IFrabricDAOSum, IFrabric {}

error ProposingNullParticipants();
error ProposingGenesisParticipants();
error InvalidAddress(address invalid);
error ExistingGovernor(address governor, IFrabric.GovernorStatus status);
error InvalidName(string name, string symbol);
error ProposingParticipantRemovalOnThread();
error ProposingFrabricChange();
error ExternalCallFailed(address called, bytes4 selector, bytes error);
error ParticipantsProposalNotPassed(uint256 id);
error ParticipantAlreadyApproved(address participant);
error InvalidKYCSignature(address signer, address kyc);
error IncorrectParticipant(address participant, bytes32 participants, bytes32[] proof);
