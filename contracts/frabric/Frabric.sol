// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ECDSAUpgradeable as ECDSA } from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

// Using a draft contract isn't great, as is using EIP712 which is technically still under "Review"
// EIP712 was created over 4 years ago and has undegone multiple versions since
// Metamask supports multiple various versions of EIP712 and is committed to maintaing "v3" and "v4" support
// The only distinction between the two is the support for arrays/structs in structs, which aren't used by this contract
// Therefore, this usage is fine, now and in the long-term, as long as one of those two versions is indefinitely supported
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

import "../interfaces/bond/IBond.sol";
import "../interfaces/thread/IThreadDeployer.sol";
import "../interfaces/thread/IThread.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IFrabric.sol";

contract Frabric is EIP712Upgradeable, FrabricDAO, IFrabric {
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
    uint256 variant;
    address agent;
    string name;
    string symbol;
    bytes data;
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
    __EIP712_init("Frabric Protocol", "1");
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

  function canPropose() public view override(IDAO, DAO) returns (bool) {
    return uint256(participant[msg.sender]) > uint256(ParticipantType.Removed);
  }

  function proposeParticipants(
    ParticipantType participantType,
    address[] memory participants,
    string calldata info
  ) external override returns (uint256) {
    if (participantType == ParticipantType.Null) {
      // CommonProposalType.ParticipantRemoval should be used
      revert ProposingNullParticipants();
    }
    if (participantType == ParticipantType.Genesis) {
      revert ProposingGenesisParticipants();
    }

    if (participants.length != 1) {
      if (participants.length == 0) {
        revert ZeroParticipants();
      }
      if ((participantType != ParticipantType.Individual) && (participantType == ParticipantType.Corporation)) {
        revert BatchParticipantsForNonBatchType(participants.length, participantType);
      }
    }

    if ((participantType == ParticipantType.Governor) && (governor[participants[0]] != GovernorStatus.Null)) {
      revert ExistingGovernor(participants[0], governor[participants[0]]);
    }

    _participants[_nextProposalID] = Participants(participantType, participants, 0);
    emit ParticipantsProposed(_nextProposalID, participantType, participants);
    return _createProposal(uint256(FrabricProposalType.Participants), info);
  }

  function proposeRemoveBond(
    address _governor,
    bool slash,
    uint256 amount,
    string calldata info
  ) external override returns (uint256) {
    _removeBond[_nextProposalID] = RemoveBondProposal(_governor, slash, amount);
    if (uint256(governor[_governor]) < uint256(GovernorStatus.Active)) {
      // Arguably a misuse as this actually checks they were never an active governor
      // Not that they aren't currently an active governor, which the error name suggests
      // This should be better to handle from an integration perspective however
      revert NotActiveGovernor(_governor, governor[_governor]);
    }
    emit RemoveBondProposed(_nextProposalID, _governor, slash, amount);
    return _createProposal(uint256(FrabricProposalType.RemoveBond), info);
  }

  function proposeThread(
    uint256 variant,
    address agent,
    string calldata name,
    string calldata symbol,
    bytes calldata data,
    string calldata info
  ) external override returns (uint256) {
    if (governor[agent] != GovernorStatus.Active) {
      revert NotActiveGovernor(agent, governor[agent]);
    }
    // Doesn't check for being alphanumeric due to iteration costs
    if ((bytes(name).length < 3) || (bytes(name).length > 50) || (bytes(symbol).length < 2) || (bytes(symbol).length > 5)) {
      revert InvalidName(name, symbol);
    }
    // Validate the data now before creating the proposal
    IThreadDeployer(threadDeployer).validate(variant, data);
    _threads[_nextProposalID] = ThreadProposal(variant, agent, name, symbol, data);
    emit ThreadProposed(_nextProposalID, variant, agent, name, symbol, data);
    return _createProposal(uint256(FrabricProposalType.Thread), info);
  }

  // This does assume the Thread's API meets expectations compiled into the Frabric
  // They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  // These are both valid behaviors intended to be accessible by Threads
  function proposeThreadProposal(
    address thread,
    uint256 _proposalType,
    bytes calldata data,
    string calldata info
  ) external returns (uint256) {
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
      } else if (pType == CommonProposalType.ParticipantRemoval) {
        // If a participant should be removed, remove them from the Frabric, not the Thread
        revert ProposingParticipantRemovalOnThread();
      } else {
        revert UnhandledEnumCase("Frabric proposeThreadProposal CommonProposal", _proposalType);
      }
    } else {
      IThread.ThreadProposalType pType = IThread.ThreadProposalType(_proposalType);
      if (pType == IThread.ThreadProposalType.AgentChange) {
        selector = IThread.proposeAgentChange.selector;
      } else if (pType == IThread.ThreadProposalType.FrabricChange) {
        // Doesn't use UnhandledEnumCase as that suggests a development-level failure to handle cases
        // While that already isn't guaranteed in this function, as _proposalType is user input,
        // it requires invalid input. Technically, FrabricChange is a legitimate enum value
        revert ProposingFrabricChange();
      } else if (pType == IThread.ThreadProposalType.Dissolution) {
        selector = IThread.proposeDissolution.selector;
      } else {
        revert UnhandledEnumCase("Frabric proposeThreadProposal ThreadProposal", _proposalType);
      }
    }

    _threadProposals[_nextProposalID] = ThreadProposalProposal(thread, selector, data);
    emit ThreadProposalProposed(_nextProposalID, thread, _proposalType, info);
    return _createProposal(uint256(FrabricProposalType.ThreadProposal), info);
  }

  function _participantRemoval(address _participant) internal override {
    if (governor[_participant] != GovernorStatus.Null) {
      governor[_participant] = GovernorStatus.Removed;
    }
    participant[_participant] = ParticipantType.Removed;
  }

  function _completeSpecificProposal(uint256 id, uint256 _pType) internal override {
    FrabricProposalType pType = FrabricProposalType(_pType);
    if (pType == FrabricProposalType.Participants) {
      Participants storage participants = _participants[id];
      if (participants.pType == ParticipantType.KYC) {
        emit KYCChanged(kyc, participants.participants[0]);
        participant[kyc] = ParticipantType.Removed;
        kyc = participants.participants[0];
        participant[participants.participants[0]] = ParticipantType.KYC;
        // Delete for the gas savings
        delete _participants[id];
      } else {
        if (participants.pType == ParticipantType.Governor) {
          // A similar check exists in proposeParticipants yet that doesn't
          // prevent the same proposal from existing multiple times. This is
          // an edge case which should never happen, yet handling it means
          // checking here to ensure if they already exist, they're not reset
          // to Unverified. While we could error here, we may as well delete
          // the invalid proposal and move on.
          if (governor[participants.participants[0]] != GovernorStatus.Null) {
            delete _participants[id];
            return;
          }
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
      IThreadDeployer(threadDeployer).deploy(
        proposal.variant, proposal.agent, proposal.name, proposal.symbol, proposal.data
      );
      delete _threads[id];

    } else if (pType == FrabricProposalType.ThreadProposal) {
      ThreadProposalProposal memory proposal = _threadProposals[id];
      (bool success, bytes memory data) = proposal.thread.call(
        abi.encodeWithSelector(proposal.selector, proposal.data)
      );
      if (!success) {
        revert ExternalCallFailed(proposal.thread, proposal.selector, data);
      }
      delete _threadProposals[id];
    } else {
      revert UnhandledEnumCase("Frabric _completeSpecificProposal", _pType);
    }
  }

  function approve(uint256 id, uint256 position, bytes32 kycHash, bytes calldata signature) external override {
    if (_participants[id].passed == 0) {
      revert ParticipantProposalNotPassed(id);
    }

    address approving = _participants[id].participants[position];
    // Technically, the original proposal may have the 0 address in it
    // That would prevent this proposal from ever fully passing and being deleted
    // That doesn't help anyone and is solely an annoyance to the Ethereum blockchain used (not even the Frabric)
    if (approving == address(0)) {
      // Doesn't include the address as it... can't. It's been deleted
      revert ParticipantAlreadyApproved();
    }
    _participants[id].participants[position] = address(0);

    // Places signer in a variable to make the information available for the error
    // While generally, the errors include an abundance of information with the expectation they'll be caught in a call,
    // and even if they are executed on chain, we don't care about the increased gas costs for the extreme minority,
    // this calculation is extensive enough it's worth the variable (which shouldn't even change gas costs?)
    address signer = ECDSA.recover(
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256("KYCVerification(address participant,bytes32 kycHash)"),
            approving,
            kycHash
          )
        )
      ),
      signature
    );
    if (signer != kyc) {
      revert InvalidKYCSignature(signer, kyc);
    }

    // There is a chance this participant was in another proposal or duplicated in this one
    // In that case, they may already have a status in participant
    // This isn't checked for during proposeParticipants due to gas costs
    // Not only would it be a full iteration, yet it'd need to set an additional variable
    // If the proposal doesn't pass, someone would have to step up and clear those variables,
    // which isn't feasible

    // We could error if they already exist in participant, yet that would prevent
    // their entry in this proposal from being cleared, which would prevent this proposal
    // from being deleted once all entires are cleared
    // If someone went through all the effort to issue this transaction, let it finish
    // It's an if check no matter what so it doesn't change the gas cost for the intended route

    // If they aren't already present, add them
    // If we blindly went ahead, they could be refiled (when they shouldn't be),
    // or they can be added back from being removed, which is the real danger in duplicate proposal presence
    // It would cache a DAO approval for arbitrarily long
    if (participant[approving] == ParticipantType.Null) {
      IFrabricERC20(erc20).setWhitelisted(approving, kycHash);
      participant[approving] = _participants[id].pType;
    }

    // If all participants have been handled, delete the proposal to claim the gas refund
    // This works becaused passed is set to 1 when the proposal is passed
    // While we could increment passed first, and then check if .passed - 1 ==,
    // which would be easier to read/understand, this is a valid transformation
    // which saves on gas
    if (_participants[id].passed == _participants[id].participants.length) {
      delete _participants[id];
    }
    // Increment the amount of participants from this proposal which were handled
    _participants[id].passed++;
  }
}
