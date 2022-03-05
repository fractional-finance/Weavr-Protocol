// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../erc20/FrabricERC20.sol";

import "../dao/DAO.sol";

contract Frabric is DAO {
  address public kyc;
  event KYCChanged(address indexed oldKYC, address indexed newKYC);

  enum ParticipantType {
    Null,
    KYC,
    Guardian,
    Individual,
    Corporation
  }
  struct Participant {
    ParticipantType participantType;
    address participant;
    bool passed;
    bool whitelisted;
  }
  mapping(uint256 => Participant) internal _participants;
  event ParticipantProposed(uint256 indexed id, address participant, uint256 indexed participantType);
  event ParticipantUpdated(uint256 indexed id, address participant);

  enum GuardianStatus {
    Null,
    Unverified, // Proposed and elected
    Active,
    Removed
  }
  mapping(address => GuardianStatus) public guardian;

  modifier beforeProposal() {
    require(FrabricERC20(erc20).whitelisted(msg.sender), "Frabric: Proposer isn't whitelisted");
    _;
  }

  // Can set to Null to remove Guardians/Individuals/Corporations
  // KYC must be replaced
  function proposeParticipant(string calldata info, uint256 participantType, address participant) external beforeProposal() returns (uint256) {
    require(participantType <= uint256(ParticipantType.Corporation), "Frabric: Invalid participant type");
    _participants[_nextProposalID] = Participant(ParticipantType(participantType), participant, false, false);
    emit ParticipantProposed(_nextProposalID, participant, participantType);
    return _createProposal(info, 0);
  }

  function _completeProposal(uint256 id, uint256 proposalType) internal override {
    Participant storage participant = _participants[id];
    participant.passed = true;
    if (proposalType == 0) {
      if (participant.participantType == ParticipantType.KYC) {
        emit KYCChanged(kyc, participant.participant);
        kyc = participant.participant;
      } else {
        emit ParticipantUpdated(id, participant.participant);
        if (participant.participantType == ParticipantType.Guardian) {
          require(guardian[participant.participant] == GuardianStatus.Null);
          guardian[participant.participant] = GuardianStatus.Unverified;
        } else if (participant.participantType == ParticipantType.Null) {
          if (guardian[participant.participant] != GuardianStatus.Null) {
            guardian[participant.participant] = GuardianStatus.Removed;
          }
          // Remove them from the whitelist
          FrabricERC20(erc20).setWhitelisted(participant.participant, bytes32(0));
        }
      }
    }
  }

  function whitelist(uint256 id, bytes32 kycHash) external {
    require(msg.sender == kyc);
    require(_participants[id].passed);
    require(!_participants[id].whitelisted);
    _participants[id].whitelisted = true;
    FrabricERC20(erc20).setWhitelisted(_participants[id].participant, kycHash);
  }
}
