// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable as IVotes } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/dao/IDAO.sol";

// DAO around a FrabricERC20
abstract contract DAO is Composable, IDAO {
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
    uint16 pType;

    // Whether or not this proposal requires a supermajority to pass
    bool supermajority;

    // The following are exposed via getters
    // This won't be deleted yet this struct is used in _proposals which atomically increments keys
    // Therefore, this usage is safe
    mapping(address => int128) voters;
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
  uint64 public override queuePeriod;

  uint256 private _nextProposalID;
  mapping(uint256 => Proposal) private _proposals;

  mapping(uint256 => bool) public override passed;

  uint256[100] private __gap;

  function __DAO_init(address _erc20, uint64 _votingPeriod) internal onlyInitializing {
    supportsInterface[type(IDAOCore).interfaceId] = true;
    supportsInterface[type(IDAO).interfaceId] = true;

    erc20 = _erc20;
    votingPeriod = _votingPeriod;
    queuePeriod = 48 hours;
  }

  // Create a fake proposal
  // Used by the Frabric to add its initial participants in a manner consistent
  // with actual usage
  function _fakeProposal(uint16 proposalType, bytes32 info) internal returns (uint256 id) {
    id = _nextProposalID;
    _nextProposalID++;

    emit NewProposal(id, proposalType, address(0), info);
    emit ProposalStateChanged(id, ProposalState.Active);
    emit ProposalStateChanged(id, ProposalState.Queued);
    emit ProposalStateChanged(id, ProposalState.Executed);
  }

  function requiredParticipation() public view returns (uint128) {
    // Uses the current total supply instead of the historical total supply in
    // order to represent the current community
    // Subtracts any reserves held by the DAO itself as those can't be voted with
    return uint128(IERC20(erc20).totalSupply() - IERC20(erc20).balanceOf(address(this))) / 10;
  }

  function canPropose(address proposer) public virtual view returns (bool);
  modifier beforeProposal() {
    if (!canPropose(msg.sender)) {
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

  function _createProposal(
    uint16 proposalType,
    bool supermajority,
    bytes32 info
  ) internal beforeProposal() returns (uint256 id) {
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
    proposal.supermajority = supermajority;

    // Separate event to allow indexing by type/creator while maintaining state machine consistency
    // Also exposes info
    emit NewProposal(id, proposalType, proposal.creator, info);
    emit ProposalStateChanged(id, proposal.state);

    // Automatically vote in favor for the creator if they have votes and are actively whitelisted
    int128 votes = int128(uint128(IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock)));
    if ((votes != 0) && IWhitelist(erc20).whitelisted(msg.sender)) {
      _voteUnsafe(msg.sender, id, proposal, votes, votes);
    }
  }

  // Labelled unsafe due to its split checks with the various callers and lack of guarantees
  // on what checks it'll perform. This can only be used in a carefully designed, cohesive ecosystemm
  function _voteUnsafe(address voter, uint256 id, Proposal storage proposal, int128 votes, int128 absVotes) private {
    // Cap voting power per user at 10% of the current total supply
    // This will hopefully not be executed 99% of the time and then only for select Threads
    // This isn't perfect yet we are somewhat sybil resistant thanks to requiring KYC
    // 10% isn't requiredParticipation, despite currently having the same value,
    // yet rather a number with some legal consideration
    // requiredParticipation was also moved to circulating supply while this remains total
    int128 tenPercent = int128(uint128(IVotes(erc20).getPastTotalSupply(proposal.voteBlock) / 10));
    if (absVotes > tenPercent) {
      votes = tenPercent * (votes / absVotes);
      absVotes = tenPercent;
    }

    // Remove old votes
    int128 standing = proposal.voters[voter];
    if (standing != 0) {
      proposal.votes -= standing;
    } else {
      // If they had previously abstained, increase the amount of total votes
      proposal.totalVotes += uint128(absVotes);
    }

    // Set new votes
    proposal.voters[voter] = votes;
    // Update the vote sums
    VoteDirection direction;
    if (votes != 0) {
      proposal.votes += votes;
      direction = votes > 0 ? VoteDirection.Yes : VoteDirection.No;
    } else {
      // If they're now abstaining, decrease the amount of total votes
      // While abstaining could be considered valid as participation,
      // it'd require an extra variable to properly track and requiring opinionation is fine
      proposal.totalVotes -= uint128(absVotes);
      direction = VoteDirection.Abstain;
    }

    emit Vote(id, direction, voter, uint128(absVotes));
  }

  function _voteUnsafe(uint256 id, address voter) internal {
    Proposal storage proposal = _proposals[id];
    int128 votes = int128(uint128(IVotes(erc20).getPastVotes(voter, proposal.voteBlock)));
    if ((votes != 0) && IWhitelist(erc20).whitelisted(voter)) {
      _voteUnsafe(voter, id, proposal, votes, votes);
    }
  }

  // While it's not expected for this to be called in batch due to UX complexities,
  // it's a very minor gas cost which does offer savings when multiple proposals
  // are voted on at the same time
  function vote(uint256[] memory ids, int128[] memory votes) external override {
    // Requires the caller to also be whitelisted. While the below NoVotes error
    // should prevent this from happening, when the Frabric removes someone,
    // Threads keep token balances until someone calls remove on them
    // This check prevents them from voting in the meantime, even though it could
    // eventually be handled by calling remove and cancelProposal when the time comes
    if (!IWhitelist(erc20).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    for (uint256 i = 0; i < ids.length; i++) {
      Proposal storage proposal = activeProposal(ids[i]);
      int128 actualVotes = int128(uint128(IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock)));
      if (actualVotes == 0) {
        return;
      }

      // Since Solidity arrays are bounds checked, this will simply error if votes
      // is too short. If it's too long, it ignores the extras, and the actually processed
      // data doesn't suffer from any mutability
      int128 votesI = votes[i];

      // If they're abstaining, don't check if they have enough votes
      // 0 will be less than whatever amount they do have
      int128 absVotes;
      if (votesI == 0) {
        absVotes = 0;
      } else {
        absVotes = votesI > 0 ? votesI : -votesI;
        // If they're voting with more votes then they actually have, correct votes
        // Also allows UIs to simply vote with type(int128).max
        if (absVotes > actualVotes) {
          // votesI / absVotes will return 1 or -1, representing the vote direction
          votesI = actualVotes * (votesI / absVotes);
        }
      }

      _voteUnsafe(msg.sender, ids[i], proposal, votesI, absVotes);
    }
  }

  function queueProposal(uint256 id) external override {
    Proposal storage proposal = _proposals[id];

    // Proposal should be Active to be queued
    if (proposal.state != ProposalState.Active) {
      revert InactiveProposal(id);
    }

    // Proposal's voting period should be over
    uint256 end = proposal.stateStartTime + votingPeriod;
    if (block.timestamp < end) {
      revert ActiveProposal(id, block.timestamp, end);
    }

    // Proposal should've gotten enough votes to pass
    int128 passingVotes = 0;
    if (proposal.supermajority) {
      // Utilize a 66% supermajority requirement
      // If 0 represents 50%, a further 16% of votes must be positive
      // Doesn't add 1 to handle rounding due to the following if statement
      passingVotes = int128(proposal.totalVotes / 6);
    }

    // In case of a tie, err on the side of caution and fail the proposal
    if (proposal.votes <= passingVotes) {
      revert ProposalFailed(id, proposal.votes);
    }

    // Require sufficient participation to ensure this actually represents the community
    if (proposal.totalVotes < requiredParticipation()) {
      revert NotEnoughParticipation(id, proposal.totalVotes, requiredParticipation());
    }

    proposal.state = ProposalState.Queued;
    proposal.stateStartTime = uint64(block.timestamp);
    emit ProposalStateChanged(id, proposal.state);
  }

  function cancelProposal(uint256 id, address[] calldata voters) external override {
    // Must be queued. Even if it's completable, if it has yet to be completed, allow this
    Proposal storage proposal = _proposals[id];
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }

    int128 newVotes = proposal.votes;
    uint160 prevVoter = 0;
    for (uint i = 0; i < voters.length; i++) {
      address voter = voters[i];
      if (uint160(voter) <= prevVoter) {
        revert UnsortedVoter(voter);
      }
      prevVoter = uint160(voter);

      // If a voter who voted against this proposal (or abstained) is included,
      // whoever wrote JS to handle this has a broken script which isn't working as intended
      int128 voted = proposal.voters[voter];
      if (voted <= 0) {
        revert NotYesVote(id, voter);
      }

      int128 votes = int128(uint128(IERC20(erc20).balanceOf(voter)));
      int128 tenPercent = int128(uint128(IVotes(erc20).getPastTotalSupply(proposal.voteBlock) / 10));
      if (votes > tenPercent) {
        votes = tenPercent;
      }

      // If they currently have enough votes to maintain their historical vote, continue
      // If we errored here, cancelProposal TXs could be vulnerable to frontrunning
      // designed to bork these cancellations
      // This will force those who sold their voting power to regain it and hold it
      // for as long as cancelProposal can be issued
      if (votes >= voted) {
        continue;
      }

      newVotes -= voted - votes;
    }

    // If votes is 0, it would've failed queueProposal
    // Fail it here as well
    if (newVotes > 0) {
      revert ProposalPassed(id, newVotes);
    }

    delete _proposals[id];
    emit ProposalStateChanged(id, ProposalState.Cancelled);
  }

  function _completeProposal(uint256 id, uint16 proposalType) internal virtual;

  // Does not require canonically ordering when executing proposals in case a proposal has invalid actions, halting everything
  // It would make a more robust system for specific proposal types, such as Thread's FrabricChange,
  // if only the most recent instance of such a proposal could be edited though
  // That is left for Thread to implement outside of the API of DAO
  function completeProposal(uint256 id) external override {
    // Safe against re-entrancy (regarding multiple execution of the same proposal)
    // as long as this block is untouched. While multiple proposals can be executed
    // simultaneously, that should not be an issue
    Proposal storage proposal = _proposals[id];
    // Cheaper than copying the entire thing into memory
    uint16 pType = proposal.pType;
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }
    uint256 end = proposal.stateStartTime + queuePeriod;
    if (block.timestamp < end) {
      revert StillQueued(id, block.timestamp, end);
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

  // Next proposal ID. Mainly useful for tests, yet also a quick way to get the
  // amount of proposals created
  function nextProposalID() external view override returns (uint256) {
    return _nextProposalID;
  }

  // Will only work with proposals which have yet to complete in some form
  // After that, the sole information available onchain is passed and proposalVote
  // as mappings aren't deleted
  function proposalVoteBlock(uint256 id) external view override returns (uint64) {
    return _proposals[id].voteBlock;
  }
  function proposalVotes(uint256 id) public view override returns (int128) {
    return _proposals[id].votes;
  }
  function proposalTotalVotes(uint256 id) external view override returns (uint128) {
    return _proposals[id].totalVotes;
  }

  function proposalVote(uint256 id, address voter) external view override returns (int128) {
    return _proposals[id].voters[voter];
  }
}
