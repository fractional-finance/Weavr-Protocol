// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "../dao/IFrabricDAO.sol";

interface IFrabric is IFrabricDAO {
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

  event KYCChanged(address indexed oldKYC, address indexed newKYC);

  event ParticipantsProposed(uint256 indexed id, ParticipantType indexed participantType, address[] participants);
  event RemoveBondProposed(uint256 indexed id, address indexed participant, bool indexed slash, uint256 amount);
  event ThreadProposed(uint256 indexed id, address indexed agent, address indexed raiseToken, uint256 target);
  event ThreadProposalProposed(uint256 indexed id, address indexed thread, uint256 indexed proposalType, string info);

  function kyc() external view returns (address);
  function bond() external view returns (address);
  function threadDeployer() external view returns (address);
  function participant(address participant) external view returns (ParticipantType);
  function governor(address governor) external view returns (GovernorStatus);

  function initialize(
    address _erc20,
    address _bond,
    address _threadDeployer,
    address[] calldata genesis,
    address _kyc
  ) external;

  function proposeParticipants(
    ParticipantType participantType,
    address[] memory participants,
    string calldata info
  ) external returns (uint256);
  function proposeRemoveBond(
    address governor,
    bool slash,
    uint256 amount,
    string calldata info
  ) external returns (uint256);
  function proposeThread(
    string memory name,
    string memory symbol,
    address agent,
    address raiseToken,
    uint256 target,
    string calldata info
  ) external returns (uint256);
  function proposeThreadProposal(
    address thread,
    uint256 proposalType,
    bytes calldata data,
    string calldata info
  ) external returns (uint256);

  function approve(uint256 id, uint256 position, bytes32 kycHash, bytes calldata signature) external;
}

error ProposingGenesisParticipants();
error ZeroParticipants();
error BatchParticipantsForNonBatchType(uint256 proposed, IFrabric.ParticipantType participantType);
error ExistingGovernor(address governor, IFrabric.GovernorStatus status);
error InvalidName(string name, string symbol);
error ProposingFrabricChange(address thread);
error ThreadProposalFailed(bytes error);
error ParticipantProposalNotPassed(uint256 id);
error ParticipantAlreadyApproved();
error InvalidKYCSignature(address signer, address kyc);