// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable as IVotes } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/dao/IDAO.sol";

// DAO around a FrabricERC20
abstract contract DAO is Initializable, Composable, IDAOSum {
  struct Proposal {
    // The following are embedded into easily accessible events
    address creator;
    ProposalState state;
    // This actually requires getting the block of the event as well, yet generally isn't needed
    uint64 stateStartTime;

    // Used by inheriting contracts
    // This is intended to be an enum (limited to the 8-bit space) with a bit flag
    // This allows 8 different categories of enums with a simple bit flag
    // If they were shifted and used as a number...
    // This could be uint24 as we have an extra byte in the slot right now, yet
    // there's no reason to when this could probably be a uint10 if those were allowed
    uint16 pType;

    // The following are exposed via getters
    // This won't be deleted yet this struct is used in _proposals which atomically increments keys
    // Therefore, this usage is safe
    mapping(address => VoteDirection) voters;
    // Safe due to the FrabricERC20 being uint112
    int128 votes;
    uint128 totalVotes;

    // We have 24 bytes left in this storage slot and it'd more gas efficient to
    // turn this into a uint256. Keeping it as uint64 gives us the option to pack
    // more in this slot in the future though
    uint64 voteBlock;
  }

  address public override erc20;
  uint64 public override votingPeriod;

  uint256 internal _nextProposalID;
  mapping(uint256 => Proposal) private _proposals;

  mapping(uint256 => bool) public override passed;

  function __DAO_init(address _erc20, uint64 _votingPeriod) internal onlyInitializing {
    supportsInterface[type(IDAO).interfaceId] = true;

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
  function proposalActive(uint256 id) external view override returns (bool) {
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

  function _createProposal(uint16 proposalType, string calldata info) internal beforeProposal() returns (uint256 id) {
    id = _nextProposalID;
    _nextProposalID++;

    Proposal storage proposal = _proposals[id];
    proposal.creator = msg.sender;
    proposal.state = ProposalState.Active;
    proposal.stateStartTime = uint64(block.timestamp);
    // Use the previous block as it's finalized
    // While the creator could have sold in this block, they can also sell over the next few weeks
    // This is why cancelProposal exists
    proposal.voteBlock = uint64(block.number) - 1;
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
    if (!IFrabricWhitelist(erc20).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    Proposal storage proposal = activeProposal(id);
    VoteDirection voted = proposal.voters[msg.sender];
    if (voted == direction) {
      revert AlreadyVotedInDirection(id, msg.sender, direction);
    }

    int128 votes = int128(uint128(IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock)));
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
      proposal.totalVotes += uint128(votes);
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
      proposal.totalVotes -= uint128(votes);
    }

    emit Vote(id, direction, msg.sender, uint256(uint128(votes)));
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
    proposal.stateStartTime = uint64(block.timestamp);
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
      int128 oldVotes = int128(uint128(IVotes(erc20).getPastVotes(voters[i], proposal.voteBlock)));
      int128 votes = int128(uint128(IERC20(erc20).balanceOf(voters[i])));
      // If this voter's balance has actually increased in the time given,
      // that'll be reflected here. While we could error, as it goes against the
      // offchain calculation and intended action of this call, erroring guarantees
      // this call will fail. By not erroring, we let the other voters have a chance
      // at still having significant enough differences to warrant cancellation
      // In the worst case, this will have increased gas cost before failing
      // Writes directly to the votes field to update it to its (more) accurate value
      proposal.votes -= int128(oldVotes - votes);
    }
    // If votes is 0, it would've failed queueProposal
    // Fail it here as well
    if (proposal.votes > 0) {
      revert ProposalPassed(id, proposal.votes);
    }

    proposal.state = ProposalState.Cancelled;
    proposal.stateStartTime = uint64(block.timestamp);
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
