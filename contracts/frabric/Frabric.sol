// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";
import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/IThreadDeployer.sol";

import "../dao/DAO.sol";

import "../interfaces/frabric/IFrabric.sol";

contract Frabric is DAO, IFrabric {
  using SafeERC20 for IERC20;

  address public override kyc;
  address public override threadDeployer;

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

  struct TokenProposal {
    address token;
    address target;
    bool mint;
    uint256 price;
    uint256 amount;
  }
  mapping(uint256 => TokenProposal) internal _tokenProposals;

  function guardian(address __guardian) external view override returns (uint256) {
    return uint256(_guardian[__guardian]);
  }

  modifier beforeProposal() {
    require(IFrabricERC20(erc20).whitelisted(msg.sender), "Frabric: Proposer isn't whitelisted");
    _;
  }

  // Can set to Null to remove Guardians/Individuals/Corporations
  // KYC must be replaced
  function proposeParticipant(string calldata info, uint256 participantType, address participant) external override beforeProposal() returns (uint256) {
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
  ) external override beforeProposal() returns (uint256) {
    require(bytes(name).length >= 3, "Frabric: Thread name has less than three characters");
    require(bytes(symbol).length >= 2, "Frabric: Thread symbol has less than two characters");
    require(_guardian[agent] == GuardianStatus.Active, "Frabric: Guardian selected to be agent isn't active");
    _threads[_nextProposalID] = ThreadProposal(name, symbol, agent, raiseToken, target);
    emit ThreadProposed(_nextProposalID, agent, raiseToken, target);
    return _createProposal(info, 1);
  }

  // This does assume the Thread's API meets expectations compiled into the Frabric
  // They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  // These are both valid behaviors intended to be accessible by Threads
  function proposeThreadProposal(string calldata info, address thread, uint256 proposalType, bytes calldata data) external beforeProposal() returns (uint256) {
    bytes4 selector;
    if (proposalType == 0) {
      selector = IThread.proposePaper.selector;
    } else if (proposalType == 1) {
      selector = IThread.proposeAgentChange.selector;
    } else if (proposalType == 2) {
      require(false, "Frabric: Can't request a Thread to change its Frabric");
    } else if (proposalType == 3) {
      selector = IThread.proposeDissolution.selector;
    } else {
      require(false, "Frabric: Unknown Thread Proposal type specified");
    }
    _threadProposals[_nextProposalID] = ThreadProposalProposal(thread, selector, info, data);
    emit ThreadProposalProposed(_nextProposalID, thread, proposalType, info);
    return _createProposal(info, 2);
  }

  function proposeTokenAction(string calldata info, address token, address target, bool mint, uint256 price, uint256 amount) external beforeProposal() returns (uint256) {
    require(mint == (token == erc20), "Frabric: Proposing minting a different token");
    // Target is ignorable. This allows simplifying the mint case where minted tokens are immediately sold
    // Also removes mutability and reduces scope
    require((price == 0) == (target == address(this)), "Frabric: Token sales must set self as the target");
    _tokenProposals[_nextProposalID] = TokenProposal(token, target, mint, price, amount);
    emit TokenActionProposed(_nextProposalID, token, target, mint, price, amount);
    return _createProposal(info, 3);
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
          require(_guardian[participant.participant] == GuardianStatus.Null);
          _guardian[participant.participant] = GuardianStatus.Unverified;
        } else if (participant.participantType == ParticipantType.Null) {
          if (_guardian[participant.participant] != GuardianStatus.Null) {
            _guardian[participant.participant] = GuardianStatus.Removed;
          }
          // Remove them from the whitelist
          IFrabricERC20(erc20).setWhitelisted(participant.participant, bytes32(0));
          // Prevent the KYC from using this proposal to whitelist them
          _participants[id].whitelisted = true;
        }
        emit ParticipantUpdated(id, participant.participant, uint256(participant.participantType));
      }
    } else if (proposalType == 1) {
      ThreadProposal memory proposal = _threads[id];
      // erc20 here is used as the parent whitelist as it's built into the Frabric ERC20
      IThreadDeployer(threadDeployer).deploy(proposal.name, proposal.symbol, erc20, proposal.agent, proposal.raiseToken, proposal.target);
    } else if (proposalType == 2) {
      (bool success, ) = _threadProposals[id].thread.call(
        abi.encodeWithSelector(
          _threadProposals[id].selector,
          abi.encodePacked(abi.encode(_threadProposals[id].info), _threadProposals[id].data)
        )
      );
      require(success, "Frabric: Creating the Thread Proposal failed");
    } else if (proposalType == 3) {
      if (_tokenProposals[id].mint) {
        IFrabricERC20(erc20).mint(_tokenProposals[id].target, _tokenProposals[id].amount);
      // The ILO DEX doesn't require transfer or even approve
      } else if (_tokenProposals[id].price == 0) {
        IERC20(_tokenProposals[id].token).safeTransfer(_tokenProposals[id].target, _tokenProposals[id].amount);
      }

      // Not else to allow direct mint + sell
      if (_tokenProposals[id].price != 0) {
        IIntegratedLimitOrderDEX(_tokenProposals[id].token).sell(_tokenProposals[id].price, _tokenProposals[id].amount);
      }
    } else {
      require(false, "Frabric: Trying to complete an unknown proposal type");
    }
  }

  function approve(uint256 id, bytes32 kycHash) external override {
    require(msg.sender == kyc, "Frabric: Only the KYC can approve users");
    require(_participants[id].passed, "Frabric: Proposal didn't pass");
    require(!_participants[id].whitelisted, "Frabric: Whitelisting has already happened");
    _participants[id].whitelisted = true;
    IFrabricERC20(erc20).setWhitelisted(_participants[id].participant, kycHash);
  }
}
