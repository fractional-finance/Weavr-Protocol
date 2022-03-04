// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/erc20/IFrabricERC20.sol";
import "../thread/ThreadDeployer.sol";

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
  event ParticipantUpdated(uint256 indexed id, address participant, uint256 indexed participantType);

  enum GuardianStatus {
    Null,
    Unverified, // Proposed and elected
    Active,
    Removed
  }
  mapping(address => GuardianStatus) public guardian;

  struct ThreadProposal {
    string name;
    string symbol;
    address agent;
    address raiseToken;
    uint256 target;
  }
  mapping(uint256 => ThreadProposal) internal _threads;
  event ThreadProposed(uint256 indexed id, address indexed agent, address indexed raiseToken, uint256 target);

  address public threadDeployer;

  modifier beforeProposal() {
    require(IFrabricERC20(erc20).whitelisted(msg.sender), "Frabric: Proposer isn't whitelisted");
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

  function proposeThread(
    string calldata info,
    string memory name,
    string memory symbol,
    address agent,
    address raiseToken,
    uint256 target
  ) external beforeProposal() returns (uint256) {
    require(bytes(name).length >= 3, "Frabric: Thread name has less than three characters");
    require(bytes(symbol).length >= 2, "Frabric: Thread symbol has less than two characters");
    require(guardian[agent] == GuardianStatus.Active, "Frabric: Guardian selected to be agent isn't active");
    _threads[_nextProposalID] = ThreadProposal(name, symbol, agent, raiseToken, target);
    emit ThreadProposed(_nextProposalID, agent, raiseToken, target);
    return _createProposal(info, 1);
  }

  function _completeProposal(uint256 id, uint256 proposalType) internal override {
    if (proposalType == 0) {
      Participant storage participant = _participants[id];
      participant.passed = true;
      if (participant.participantType == ParticipantType.KYC) {
        emit KYCChanged(kyc, participant.participant);
        kyc = participant.participant;
      } else {
        if (participant.participantType == ParticipantType.Guardian) {
          require(guardian[participant.participant] == GuardianStatus.Null);
          guardian[participant.participant] = GuardianStatus.Unverified;
        } else if (participant.participantType == ParticipantType.Null) {
          if (guardian[participant.participant] != GuardianStatus.Null) {
            guardian[participant.participant] = GuardianStatus.Removed;
          }
          // Remove them from the whitelist
          IFrabricERC20(erc20).setWhitelisted(participant.participant, bytes32(0));
        }
        emit ParticipantUpdated(id, participant.participant, uint256(participant.participantType));
      }
    } else if (proposalType == 1) {
      ThreadProposal memory proposal = _threads[id];
      // erc20 here is used as the parent whitelist as it's built into the Frabric ERC20
      ThreadDeployer(threadDeployer).deploy(proposal.name, proposal.symbol, erc20, proposal.agent, proposal.raiseToken, proposal.target);
    }
  }

  function whitelist(uint256 id, bytes32 kycHash) external {
    require(msg.sender == kyc);
    require(_participants[id].passed);
    require(!_participants[id].whitelisted);
    _participants[id].whitelisted = true;
    IFrabricERC20(erc20).setWhitelisted(_participants[id].participant, kycHash);
  }
}
