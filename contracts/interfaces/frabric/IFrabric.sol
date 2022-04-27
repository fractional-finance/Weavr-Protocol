// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IUpgradeable.sol";
import "../dao/IFrabricDAO.sol";

interface IFrabricCore is IFrabricDAO {
  enum GovernorStatus {
    Null,
    Active,
    // Removed is last as GovernorStatus is written as a linear series of transitions
    // > Unverified will work to find any Governor which was ever active
    Removed
  }

  function governor(address governor) external view returns (GovernorStatus);
}

interface IFrabric is IFrabricCore {
  enum FrabricProposalType {
    Participant,
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
    Voucher,
    Individual,
    Corporation
  }

  event ParticipantProposal(
    uint256 indexed id,
    ParticipantType indexed participantType,
    address participant
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
  event ParticipantChange(ParticipantType indexed participantType, address indexed participant);
  event Vouch(address indexed voucher, address indexed vouchee);
  event KYC(address indexed kyc, address indexed participant);

  function participant(address participant) external view returns (ParticipantType);

  function bond() external view returns (address);
  function threadDeployer() external view returns (address);

  function vouchers(address) external view returns (uint256);

  function proposeParticipant(
    ParticipantType participantType,
    address participant,
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

  function vouch(address participant, bytes calldata signature) external;
  function approve(
    ParticipantType pType,
    address approving,
    bytes32 kycHash,
    bytes calldata signature
  ) external;
}

interface IFrabricUpgradeable is IFrabric, IUpgradeable {}

error InvalidParticipantType(IFrabric.ParticipantType pType);
error ParticipantAlreadyApproved(address participant);
error InvalidName(string name, string symbol);
error OutOfVouchers(address voucher);
error DifferentParticipantType(address participant, IFrabric.ParticipantType current, IFrabric.ParticipantType expected);
error InvalidKYCSignature(address signer, IFrabric.ParticipantType status);
