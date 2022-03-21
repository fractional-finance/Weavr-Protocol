// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/bond/IBond.sol";
import "../interfaces/thread/IThreadDeployer.sol";
import "../interfaces/thread/IThread.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IFrabric.sol";

contract Frabric is FrabricDAO, IFrabric {
  address public override kyc;
  address public override bond;
  address public override threadDeployer;

  // The proposal structs are internal as their events are easily grabbed and contain the needed information

  struct Participants {
    ParticipantType pType;
    address[] participants;
    uint256 passed;
  }
  mapping(uint256 => Participants) internal _participants;
  mapping(address => ParticipantType) public participant;
  mapping(address => GovernorStatus) public governor;

  struct RemoveBondProposal {
    address governor;
    bool slash;
    uint256 amount;
  }
  mapping(uint256 => RemoveBondProposal) internal _removeBond;

  struct ThreadProposal {
    string name;
    string symbol;
    address agent;
    address tradeToken;
    uint256 target;
  }
  mapping(uint256 => ThreadProposal) internal _threads;

  struct ThreadProposalProposal {
    address thread;
    bytes4 selector;
    bytes data;
  }
  mapping(uint256 => ThreadProposalProposal) internal _threadProposals;

  // The erc20 is expected to be fully initialized via JS during deployment
  function initialize(
    address _erc20,
    address _bond,
    address _threadDeployer,
    address[] calldata genesis,
    address _kyc
  ) external initializer {
    __FrabricDAO_init(_erc20, 2 weeks);

    // Simulate a full DAO proposal to add the genesis participants
    emit ParticipantsProposed(_nextProposalID, ParticipantType.Genesis, genesis);
    emit NewProposal(_nextProposalID, uint256(FrabricProposalType.Participants), address(0), "Genesis Participants");
    emit ProposalStateChanged(_nextProposalID, ProposalState.Active);
    emit ProposalStateChanged(_nextProposalID, ProposalState.Queued);
    emit ProposalStateChanged(_nextProposalID, ProposalState.Executed);
    // Update the proposal ID to ensure a lack of collision with the first actual DAO proposal
    _nextProposalID++;
    // Actually add the genesis participants
    for (uint256 i = 0; i < genesis.length; i++) {
      participant[genesis[i]] = ParticipantType.Genesis;
    }

    kyc = _kyc;
    bond = _bond;
    threadDeployer = _threadDeployer;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function canPropose() public view override(IFrabricDAO, FrabricDAO) returns (bool) {
    return participant[msg.sender] != ParticipantType.Null;
  }

  // Can set to Null to remove Governors/Individuals/Corporations
  // KYC must be replaced
  function proposeParticipants(
    ParticipantType participantType,
    address[] memory participants,
    string calldata info
  ) external override beforeProposal() returns (uint256) {
    require(participantType != ParticipantType.Genesis, "Frabric: Cannot propose genesis participants after genesis");
    if (participants.length != 1) {
      require(participants.length != 0, "Frabric: Proposing zero participants");
      require(
        (participantType == ParticipantType.Individual) || (participantType == ParticipantType.Corporation),
        "Frabric: Batch proposing privileged roles"
      );
    }
    _participants[_nextProposalID] = Participants(participantType, participants, 0);
    emit ParticipantsProposed(_nextProposalID, participantType, participants);
    return _createProposal(info, uint256(FrabricProposalType.Participants));
  }

  function proposeRemoveBond(
    address _governor,
    bool slash,
    uint256 amount,
    string calldata info
  ) external override beforeProposal() returns (uint256) {
    _removeBond[_nextProposalID] = RemoveBondProposal(_governor, slash, amount);
    require(uint256(governor[_governor]) >= uint256(GovernorStatus.Active), "Frabric: Governor was never active");
    emit RemoveBondProposed(_nextProposalID, _governor, slash, amount);
    return _createProposal(info, uint256(FrabricProposalType.RemoveBond));
  }

  function proposeThread(
    string memory name,
    string memory symbol,
    address agent,
    address tradeToken,
    uint256 target,
    string calldata info
  ) external override beforeProposal() returns (uint256) {
    require(bytes(name).length >= 3, "Frabric: Thread name has less than three characters");
    require(bytes(symbol).length >= 2, "Frabric: Thread symbol has less than two characters");
    require(governor[agent] == GovernorStatus.Active, "Frabric: Governor selected to be agent isn't active");
    _threads[_nextProposalID] = ThreadProposal(name, symbol, agent, tradeToken, target);
    emit ThreadProposed(_nextProposalID, agent, tradeToken, target);
    return _createProposal(info, uint256(FrabricProposalType.Thread));
  }

  // This does assume the Thread's API meets expectations compiled into the Frabric
  // They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  // These are both valid behaviors intended to be accessible by Threads
  function proposeThreadProposal(
    address thread,
    uint256 _proposalType,
    bytes calldata data,
    string calldata info
  ) external beforeProposal() returns (uint256) {
    // Lock down the selector to prevent arbitrary calls
    // While data is still arbitrary, it has reduced scope thanks to this, and can only be decoded in expected ways
    bytes4 selector;
    if ((_proposalType & commonProposalBit) == commonProposalBit) {
      CommonProposalType pType = CommonProposalType(_proposalType ^ commonProposalBit);
      if (pType == CommonProposalType.Paper) {
        selector = IFrabricDAO.proposePaper.selector;
      } else if (pType == CommonProposalType.Upgrade) {
        selector = IFrabricDAO.proposeUpgrade.selector;
      } else if (pType == CommonProposalType.TokenAction) {
        selector = IFrabricDAO.proposeTokenAction.selector;
      } else {
        require(false, "Frabric: Unhandled CommonProposalType in proposeThreadProposal");
      }
    } else {
      IThread.ThreadProposalType pType = IThread.ThreadProposalType(_proposalType);
      if (pType == IThread.ThreadProposalType.AgentChange) {
        selector = IThread.proposeAgentChange.selector;
      } else if (pType == IThread.ThreadProposalType.FrabricChange) {
        require(false, "Frabric: Can't request a Thread to change its Frabric");
      } else if (pType == IThread.ThreadProposalType.Dissolution) {
        selector = IThread.proposeDissolution.selector;
      } else {
        require(false, "Frabric: Unhandled ThreadProposalType in proposeThreadProposal");
      }
    }

    _threadProposals[_nextProposalID] = ThreadProposalProposal(thread, selector, data);
    emit ThreadProposalProposed(_nextProposalID, thread, _proposalType, info);
    return _createProposal(info, uint256(FrabricProposalType.ThreadProposal));
  }

  function _completeSpecificProposal(uint256 id, uint256 _pType) internal override {
    FrabricProposalType pType = FrabricProposalType(_pType);
    if (pType == FrabricProposalType.Participants) {
      Participants storage participants = _participants[id];
      if (participants.pType == ParticipantType.KYC) {
        emit KYCChanged(kyc, participants.participants[0]);
        kyc = participants.participants[0];
        // Delete for the gas savings
        delete _participants[id];
      } else {
        if (participants.pType == ParticipantType.Null) {
          if (governor[participants.participants[0]] != GovernorStatus.Null) {
            governor[participants.participants[0]] = GovernorStatus.Removed;
          }

          // Remove them from the whitelist
          IFrabricERC20(erc20).setWhitelisted(participants.participants[0], bytes32(0));
          // Clear their status
          participant[participants.participants[0]] = ParticipantType.Null;
          // Not only saves gas yet also fixes a security issue
          // Without this, the KYC company could use this removing proposal to whitelist them
          // The early return after this avoids the issue as well (as it's before passed is set),
          // yet security in depth is great
          delete _participants[id];

          return;
        } else if (participants.pType == ParticipantType.Governor) {
          require(governor[participants.participants[0]] == GovernorStatus.Null, "Frabric: Governor already exists");
          governor[participants.participants[0]] = GovernorStatus.Unverified;
        }

        // Set this proposal as having passed so the KYC company can whitelist
        participants.passed = 1;
      }

    } else if (pType == FrabricProposalType.RemoveBond) {
      if (_removeBond[id].slash) {
        IBond(bond).slash(_removeBond[id].governor, _removeBond[id].amount);
      } else {
        IBond(bond).unbond(_removeBond[id].governor, _removeBond[id].amount);
      }

    } else if (pType == FrabricProposalType.Thread) {
      ThreadProposal memory proposal = _threads[id];
      // erc20 here is used as the parent whitelist as it's built into the Frabric ERC20
      IThreadDeployer(threadDeployer).deploy(proposal.name, proposal.symbol, erc20, proposal.agent, proposal.tradeToken, proposal.target);
      delete _threads[id];

    } else if (pType == FrabricProposalType.ThreadProposal) {
      (bool success, ) = _threadProposals[id].thread.call(
        abi.encodeWithSelector(_threadProposals[id].selector, _threadProposals[id].data)
      );
      require(success, "Frabric: Creating the Thread Proposal failed");
      delete _threadProposals[id];
    } else {
      require(false, "Frabric: Trying to complete an unknown proposal type");
    }
  }

  function approve(uint256 id, uint256 position, bytes32 kycHash) external override {
    require(msg.sender == kyc, "Frabric: Only the KYC can approve users");
    require(_participants[id].passed != 0, "Frabric: Proposal didn't pass");

    address approving = _participants[id].participants[position];
    require(approving != address(0), "Frabric: Participant already approved");
    require(participant[approving] == ParticipantType.Null, "Frabric: Participant already a participant");
    _participants[id].participants[position] = address(0);

    IFrabricERC20(erc20).setWhitelisted(approving, kycHash);
    participant[approving] = _participants[id].pType;

    _participants[id].passed++;
    if ((_participants[id].passed - 1) == _participants[id].participants.length) {
      delete _participants[id];
    }
  }
}
