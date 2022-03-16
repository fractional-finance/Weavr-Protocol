// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/IThreadDeployer.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IFrabric.sol";

contract Frabric is FrabricDAO, IFrabric {
  address public override kyc;
  address public override threadDeployer;

  enum FrabricProposalType {
    Participant,
    Thread,
    ThreadProposal
  }

  // Almost all of these are internal as their events are easily grabbed and contain the needed information
  // whitelisted/balanceOf exposes if someone is an active participant
  // guardian is a getter to view their statuses more easily and let other contracts perform checks

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
  }
  mapping(uint256 => Participant) internal _participants;

  enum GuardianStatus {
    Null,
    Unverified, // Proposed and elected
    Active,
    Removed
  }
  mapping(address => GuardianStatus) internal _guardian;

  struct ThreadProposal {
    string name;
    string symbol;
    address agent;
    address raiseToken;
    uint256 target;
  }
  mapping(uint256 => ThreadProposal) internal _threads;

  struct ThreadProposalProposal {
    address thread;
    bytes4 selector;
    string info;
    bytes data;
  }
  mapping(uint256 => ThreadProposalProposal) internal _threadProposals;

  function guardian(address __guardian) external view override returns (uint256) {
    return uint256(_guardian[__guardian]);
  }

  function canPropose() public view override(IFrabricDAO, FrabricDAO) returns (bool) {
    return IFrabricERC20(erc20).whitelisted(msg.sender);
  }

  // Can set to Null to remove Guardians/Individuals/Corporations
  // KYC must be replaced
  function proposeParticipant(string calldata info, uint256 participantType, address participant) external override beforeProposal() returns (uint256) {
    _participants[_nextProposalID] = Participant(ParticipantType(participantType), participant, false);
    emit ParticipantProposed(_nextProposalID, participant, participantType);
    return _createProposal(info, uint256(FrabricProposalType.Participant));
  }

  function proposeThread(
    string calldata info,
    string memory name,
    string memory symbol,
    address agent,
    address raiseToken,
    uint256 target
  ) external override beforeProposal() returns (uint256) {
    require(bytes(name).length >= 3, "Frabric: Thread name has less than three characters");
    require(bytes(symbol).length >= 2, "Frabric: Thread symbol has less than two characters");
    require(_guardian[agent] == GuardianStatus.Active, "Frabric: Guardian selected to be agent isn't active");
    _threads[_nextProposalID] = ThreadProposal(name, symbol, agent, raiseToken, target);
    emit ThreadProposed(_nextProposalID, agent, raiseToken, target);
    return _createProposal(info, uint256(FrabricProposalType.Thread));
  }

  // This does assume the Thread's API meets expectations compiled into the Frabric
  // They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  // These are both valid behaviors intended to be accessible by Threads
  function proposeThreadProposal(string calldata info, address thread, uint256 _proposalType, bytes calldata data) external beforeProposal() returns (uint256) {
    // Lock down the selector to prevent arbitrary calls
    // While data is still arbitrary, it has reduced scope thanks to this, and can be decoded in expected ways
    bytes4 selector;
    if ((_proposalType & commonProposalBit) == commonProposalBit) {
      CommonProposalType proposalType = CommonProposalType(_proposalType ^ commonProposalBit);
      if (proposalType == CommonProposalType.Paper) {
        selector = IFrabricDAO.proposePaper.selector;
      } else if (proposalType == CommonProposalType.Upgrade) {
        selector = IFrabricDAO.proposeUpgrade.selector;
      } else if (proposalType == CommonProposalType.TokenAction) {
        selector = IFrabricDAO.proposeTokenAction.selector;
      } else {
        require(false, "Frabric: Unhandled CommonProposalType in proposeThreadProposal");
      }
    } else {
      IThread.ThreadProposalType proposalType = IThread.ThreadProposalType(_proposalType);
      if (proposalType == IThread.ThreadProposalType.AgentChange) {
        selector = IThread.proposeAgentChange.selector;
      } else if (proposalType == IThread.ThreadProposalType.FrabricChange) {
        require(false, "Frabric: Can't request a Thread to change its Frabric");
      } else if (proposalType == IThread.ThreadProposalType.Dissolution) {
        selector = IThread.proposeDissolution.selector;
      } else {
        require(false, "Frabric: Unhandled ThreadProposalType in proposeThreadProposal");
      }
    }

    _threadProposals[_nextProposalID] = ThreadProposalProposal(thread, selector, info, data);
    emit ThreadProposalProposed(_nextProposalID, thread, _proposalType, info);
    return _createProposal(info, uint256(FrabricProposalType.ThreadProposal));
  }

  function _completeSpecificProposal(uint256 id, uint256 _proposalType) internal override {
    FrabricProposalType proposalType = FrabricProposalType(_proposalType);
    if (proposalType == FrabricProposalType.Participant) {
      Participant storage participant = _participants[id];
      if (participant.participantType == ParticipantType.KYC) {
        emit KYCChanged(kyc, participant.participant);
        kyc = participant.participant;
        // Delete for the gas savings
        delete _participants[id];
      } else {
        emit ParticipantUpdated(id, participant.participant, uint256(participant.participantType));
        if (participant.participantType == ParticipantType.Null) {
          if (_guardian[participant.participant] != GuardianStatus.Null) {
            _guardian[participant.participant] = GuardianStatus.Removed;
          }

          // Remove them from the whitelist
          IFrabricERC20(erc20).setWhitelisted(participant.participant, bytes32(0));
          // Not only saves gas yet also fixes a security issue
          // Without this, the KYC company could use this removing proposal to whitelist them
          // The early return after this avoids the issue as well, yet security in depth is great
          delete _participants[id];

          return;
        }

        if (participant.participantType == ParticipantType.Guardian) {
          require(_guardian[participant.participant] == GuardianStatus.Null, "Frabric: Guardian already exists");
          _guardian[participant.participant] = GuardianStatus.Unverified;
        }

        // Set this proposal as having passed so the KYC company can whitelist
        participant.passed = true;
      }

    } else if (proposalType == FrabricProposalType.Thread) {
      ThreadProposal memory proposal = _threads[id];
      // erc20 here is used as the parent whitelist as it's built into the Frabric ERC20
      IThreadDeployer(threadDeployer).deploy(proposal.name, proposal.symbol, erc20, proposal.agent, proposal.raiseToken, proposal.target);
      delete _threads[id];

    } else if (proposalType == FrabricProposalType.ThreadProposal) {
      (bool success, ) = _threadProposals[id].thread.call(
        abi.encodeWithSelector(
          _threadProposals[id].selector,
          abi.encodePacked(abi.encode(_threadProposals[id].info), _threadProposals[id].data)
        )
      );
      require(success, "Frabric: Creating the Thread Proposal failed");
      delete _threadProposals[id];
    } else {
      require(false, "Frabric: Trying to complete an unknown proposal type");
    }
  }

  function approve(uint256 id, bytes32 kycHash) external override {
    require(msg.sender == kyc, "Frabric: Only the KYC can approve users");
    require(_participants[id].passed, "Frabric: Proposal didn't pass");
    IFrabricERC20(erc20).setWhitelisted(_participants[id].participant, kycHash);
    delete _participants[id];
  }
}
