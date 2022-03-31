// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable as IVotes } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/dao/IDAO.sol";

// DAO around a FrabricERC20
abstract contract DAO is Initializable, IDAO {
  struct Proposal {
    // The following are embedded into easily accessible events
    address creator;
    ProposalState state;
    // This actually requires getting the block of the event as well, yet generally isn't needed
    uint256 stateStartTime;

    // The following are exposed via getters
    uint256 voteBlock;
    mapping(address => VoteDirection) voters;
    // Safe due to the FrabricERC20 being uint224
    int256 votes;
    uint256 totalVotes;

    // Used by inheriting contracts
    uint256 pType;
  }

  address public override erc20;
  uint256 public override votingPeriod;

  uint256 internal _nextProposalID;
  mapping(uint256 => Proposal) private _proposals;

  mapping(uint256 => bool) public override passed;

  function __DAO_init(address _erc20, uint256 _votingPeriod) internal onlyInitializing {
    erc20 = _erc20;
    votingPeriod = _votingPeriod;
  }

  function canPropose() public virtual view returns (bool);
  modifier beforeProposal() {
    if (!canPropose()) {
      revert NotAuthorizedToPropose(msg.sender);
    }
    _;
  }

  // Uses storage as all proposals checked for activity are storage
  function proposalActive(Proposal storage proposal) private view returns (bool) {
    return (
      (proposal.state == ProposalState.Active) &&
      (block.timestamp < (proposal.stateStartTime + votingPeriod))
    );
  }

  // proposal.state == ProposalState.Active isn't reliable as expired proposals which didn't pass
  // will forever have their state set to ProposalState.Active
  // This call will check the proposal's expiry status as well
  function proposalActive(uint256 id) public view override returns (bool) {
    return proposalActive(_proposals[id]);
  }

  // Used to be a modifier yet that caused the modifier to perform a map read,
  // just for the function to do the same. By making this an private function
  // returning the storage reference, it maintains performance and functions the same
  function activeProposal(uint256 id) private view returns (Proposal storage proposal) {
    proposal = _proposals[id];
    if (!proposalActive(proposal)) {
      // Doesn't include the inactivity reason as proposalActive doesn't return it
      revert InactiveProposal(id);
    }
  }

  function _createProposal(uint256 proposalType, string calldata info) internal beforeProposal() returns (uint256 id) {
    id = _nextProposalID;
    _nextProposalID++;

    Proposal storage proposal = _proposals[id];
    proposal.creator = msg.sender;
    proposal.state = ProposalState.Active;
    proposal.stateStartTime = block.timestamp;
    // Use the previous block as it's finalized
    // While the creator could have sold in this block, they can also sell over the next few weeks
    // This is why cancelProposal exists
    proposal.voteBlock = block.number - 1;
    proposal.pType = proposalType;

    // Separate event to allow indexing by type/creator while maintaining state machine consistency
    // Also exposes info
    emit NewProposal(id, proposalType, proposal.creator, info);
    emit ProposalStateChanged(id, proposal.state);

    // Automatically vote Yes for the creator
    if (IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock) != 0) {
      vote(id, VoteDirection.Yes);
    }
  }

  function vote(uint256 id, VoteDirection direction) public override {
    // Requires the caller to also be whitelisted. While the below NoVotes error
    // should prevent this from happening, when the Frabric removes someone,
    // Threads keep token balances until someone calls remove on them
    // This check prevents them from voting in the meantime, even though it could
    // eventually be handled by calling remove and cancelProposal when the time comes
    if (!IFrabricERC20(erc20).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    Proposal storage proposal = activeProposal(id);
    VoteDirection voted = proposal.voters[msg.sender];
    if (voted == direction) {
      revert AlreadyVotedInDirection(id, msg.sender, direction);
    }

    int256 votes = int256(IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock));
    if (votes == 0) {
      revert NoVotes(msg.sender);
    }
    // Remove old votes
    if (voted == VoteDirection.Yes) {
      proposal.votes -= votes;
    } else if (voted == VoteDirection.No) {
      proposal.votes += votes;
    } else {
      // If they had previously abstained, increase the amount of total votes
      proposal.totalVotes += uint256(votes);
    }

    // Set new votes
    proposal.voters[msg.sender] = direction;
    if (direction == VoteDirection.Yes) {
      proposal.votes += votes;
    } else if (direction == VoteDirection.No) {
      proposal.votes -= votes;
    } else {
      // If they're now abstaining, decrease the amount of total votes
      // While abstaining could be considered valid as participation,
      // it'd require an extra variable to track and requiring opinionation is fine
      proposal.totalVotes -= uint256(votes);
    }

    emit Vote(id, direction, msg.sender, uint256(votes));
  }

  function queueProposal(uint256 id) external {
    Proposal storage proposal = _proposals[id];
    // Proposal should be Active to be queued
    if (proposal.state != ProposalState.Active) {
      revert InactiveProposal(id);
    }
    // Proposal's voting period should be over
    if (block.timestamp < (proposal.stateStartTime + votingPeriod)) {
      revert ActiveProposal(id, block.timestamp, proposal.stateStartTime + votingPeriod);
    }
    // In case of a tie, err on the side of caution and fail the proposal
    if (proposal.votes <= 0) {
      revert ProposalFailed(id, proposal.votes);
    }
    // Uses the current total supply instead of the historical total supply to represent the current community
    if (proposal.totalVotes < (IERC20(erc20).totalSupply() / 10)) {
      revert NotEnoughParticipation(id, proposal.totalVotes, IERC20(erc20).totalSupply() / 10);
    }
    proposal.state = ProposalState.Queued;
    proposal.stateStartTime = block.timestamp;
    emit ProposalStateChanged(id, proposal.state);
  }

  function cancelProposal(uint256 id, address[] calldata voters) external {
    // Must be queued. Even if it's completable, if it has yet to be completed, allow this
    Proposal storage proposal = _proposals[id];
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }

    for (uint i = 0; i < voters.length; i++) {
      if (proposal.voters[voters[i]] != VoteDirection.Yes) {
        revert NotYesVote(id, voters[i]);
      }
      uint256 oldVotes = IVotes(erc20).getPastVotes(voters[i], proposal.voteBlock);
      uint256 votes = IERC20(erc20).balanceOf(voters[i]);
      // This will error if their votes have actually increased since
      // That would enable front running cancellation TXs with bumps of a single account
      // This shouldn't be a feasible attack vector given retries though
      // Writes directly to the votes to update it to its (more) accurate value
      proposal.votes -= int256(oldVotes - votes);
    }
    // If votes is 0, it would've failed queueProposal
    // Fail it here as well
    if (proposal.votes > 0) {
      revert ProposalPassed(id, proposal.votes);
    }

    proposal.state = ProposalState.Cancelled;
    proposal.stateStartTime = block.timestamp;
    emit ProposalStateChanged(id, proposal.state);
  }

  function _completeProposal(uint256 id, uint256 proposalType) internal virtual;

  // Does not require canonically ordering when executing proposals in case a proposal has invalid actions, halting everything
  function completeProposal(uint256 id) external {
    if (IFrabricERC20(erc20).paused()) {
      revert CurrentlyPaused();
    }

    // Safe against re-entrancy (regarding multiple execution of the same proposal)
    // as long as this block is untouched. While multiple proposals can be executed
    // simultaneously, that should not be an issue
    Proposal storage proposal = _proposals[id];
    // Cheaper than copying the entire thing into memory
    uint256 pType = proposal.pType;
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }
    if (block.timestamp < (proposal.stateStartTime + (12 hours))) {
      revert StillQueued(id, block.timestamp, proposal.stateStartTime + (12 hours));
    }
    delete _proposals[id];
    // Solely used for getter functionality
    // While we could use it for state checks, we already need to check it's specifically Queued
    passed[id] = true;
    emit ProposalStateChanged(id, ProposalState.Executed);

    // Re-entrancy here would do nothing as the proposal has had its state updated
    _completeProposal(id, pType);
  }

  // Enables withdrawing a proposal
  function withdrawProposal(uint256 id) external override {
    Proposal storage proposal = _proposals[id];
    // A proposal which didn't pass will pass this check
    // It's not worth checking the timestamp when marking the proposal as Cancelled is more accurate than Active anyways
    if ((proposal.state != ProposalState.Active) && (proposal.state != ProposalState.Queued)) {
      revert AlreadyFinished(id, proposal.state);
    }
    // Only allow the proposer to withdraw a proposal.
    if (proposal.creator != msg.sender) {
      revert NotProposalCreator(id, proposal.creator, msg.sender);
    }
    delete _proposals[id];
    emit ProposalStateChanged(id, ProposalState.Cancelled);
  }

  function proposalVoteBlock(uint256 id) external view override returns (uint256) {
    return _proposals[id].voteBlock;
  }
  function proposalVoteDirection(uint256 id, address voter) external view override returns (VoteDirection) {
    return _proposals[id].voters[voter];
  }
  function proposalVotes(uint256 id) external view override returns (int256) {
    return _proposals[id].votes;
  }
  function proposalTotalVotes(uint256 id) external view override returns (uint256) {
    return _proposals[id].totalVotes;
  }
}
