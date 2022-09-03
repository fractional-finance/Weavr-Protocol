// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IVotesUpgradeable as IVotes } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/dao/IDAO.sol";

/**
 * @title DAO Contract
 * @author Fractional Finance
 * @notice This contracts, based around a FrabricERC20, implements the core logic used by all DAOs in the ecosystem
 * @dev Upgradeable contract
 */
abstract contract DAO is Composable, IDAO {
  struct ProposalStruct {
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
    mapping(address => int112) voters;
    // Safe due to the FrabricERC20 being int112 as well
    int112 votes;
    uint112 totalVotes;
    // This would be the 2038 problem if this was denominated in seconds, which
    // wouldn't be acceptable. Instead, since it's denominated in blocks, we have
    // not 68 years from the epoch yet ~884 years from the start of Ethereum
    // Accepting the protocol's forced upgrade/death at that point to save
    // a decent amount of gas now is worth it
    // It may be much sooner if the block time decreases significantly yet
    // this is solely used in maps, which means we can extend this struct without
    // issue
    uint32 voteBlock;
  }

  /// @notice Address of the FrabricERC20 used by this DAO
  address public override erc20;
  /// @notice Proposal voting period length in seconds
  uint64 public override votingPeriod;
  /// @notice Time before a passed proposal can be enacted
  uint64 public override queuePeriod;
  /// @notice Time a proposal can be enacted before no longer being completable
  uint64 public override lapsePeriod;

  uint256 private _nextProposalID;
  mapping(uint256 => ProposalStruct) private _proposals;

  /// @notice Whether or not a proposal passed
  mapping(uint256 => bool) public override passed;

  uint256[100] private __gap;

  function __DAO_init(address _erc20, uint64 _votingPeriod) internal onlyInitializing {
    supportsInterface[type(IDAOCore).interfaceId] = true;
    supportsInterface[type(IDAO).interfaceId] = true;

    erc20 = _erc20;
    votingPeriod = _votingPeriod;
    queuePeriod = 10 seconds;
    lapsePeriod = 10 hours;
  }


  /// @notice Get required amount of participation for a proposal to passable
  /// @return uint112 Amount of participation required
  function requiredParticipation() public view returns (uint112) {
    // Uses the current total supply instead of the historical total supply in
    // order to represent the current community
    // Subtracts any reserves held by the DAO itself as those can't be voted with
    // Requires 10% participation
    return uint112(IERC20(erc20).totalSupply() - IERC20(erc20).balanceOf(address(this))) / 10;
  }

  /// @notice Check if `proposer` can propose
  /// @return bool true if `proposer` can propose, false otherwise
  /// @dev Check to be implemented by inheriting contracts
  function canPropose(address proposer) public virtual view returns (bool);
  modifier beforeProposal() {
    if (!canPropose(msg.sender)) {
      // Presumably a lack of whitelisting
      revert NotWhitelisted(msg.sender);
    }
    _;
  }

  // Uses storage as all proposals checked for activity are storage
  function proposalActive(ProposalStruct storage proposal) private view returns (bool) {
    return (
      (proposal.state == ProposalState.Active) &&
      (block.timestamp < (proposal.stateStartTime + votingPeriod))
    );
  }

  /**
   * @notice Check if proposal `id` is currently active
   * @param id ID of proposal to be checked
   * @return bool true if proposal `id` is active, false otherwise
   * @dev proposal.state == ProposalState.Active is not reliable as expired proposals
   * which didn't pass will forever have their state set to ProposalState.Active
   * This call will check the proposal's expiry status as well
  */
  function proposalActive(uint256 id) external view override returns (bool) {
    return proposalActive(_proposals[id]);
  }

  // Used to be a modifier yet that caused the modifier to perform a map read,
  // just for the function to do the same. By making this an private function
  // returning the storage reference, it maintains performance and functions the same
  function activeProposal(uint256 id) private view returns (ProposalStruct storage proposal) {
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

    ProposalStruct storage proposal = _proposals[id];
    proposal.creator = msg.sender;
    proposal.state = ProposalState.Active;
    proposal.stateStartTime = uint64(block.timestamp);
    // Use the previous block as it's finalized
    // While the creator could have sold in this block, they can also sell over the next few weeks
    // This is why cancelProposal exists
    proposal.voteBlock = uint32(block.number) - 1;
    proposal.pType = proposalType;
    proposal.supermajority = supermajority;

    // Separate event to allow indexing by type/creator while maintaining state machine consistency
    // Also exposes info
    emit Proposal(id, proposalType, proposal.creator, supermajority, info);
    emit ProposalStateChange(id, proposal.state);

    // Automatically vote in favor for the creator if they have votes and are actively KYCd
    _voteUnsafe(id, msg.sender);
  }

  // Labeled unsafe due to its split checks with the various callers and lack of guarantees
  // on what checks it'll perform. This can only be used in a carefully designed, cohesive ecosystemm
  function _voteUnsafe(
    address voter,
    uint256 id,
    ProposalStruct storage proposal,
    int112 votes,
    int112 absVotes
  ) private {
    // Cap voting power per user at 10% of the current total supply, a legally valuable number
    // This will hopefully not be executed 99% of the time and then only for select Threads
    // This isn't perfect yet we are somewhat sybil resistant thanks to requiring KYC
    // 10% isn't requiredParticipation, despite currently having the same value,
    // yet rather a number with some legal consideration
    // requiredParticipation was also moved to circulating supply while this remains total
    int112 tenPercent = int112(uint112(IVotes(erc20).getPastTotalSupply(proposal.voteBlock) / 10));
    if (absVotes > tenPercent) {
      votes = tenPercent * (votes / absVotes);
      absVotes = tenPercent;
    }

    // Remove old votes
    int112 standing = proposal.voters[voter];
    if (standing != 0) {
      proposal.votes -= standing;
      // Decrease from totalVotes as well in case the participant no longer feels as strongly
      if (standing < 0) {
        standing = -standing;
      }
      proposal.totalVotes -= uint112(standing);
    }
    // Increase the amount of total votes
    // If they're now abstaining, these will mean totalVotes is not increased at all
    // While explicitly abstaining could be considered valid as participation,
    // requiring opinionation is simpler and fine
    proposal.totalVotes += uint112(absVotes);

    // Set new votes
    proposal.voters[voter] = votes;
    // Update the vote sums
    VoteDirection direction;
    if (votes != 0) {
      proposal.votes += votes;
      direction = votes > 0 ? VoteDirection.Yes : VoteDirection.No;
    } else {
      direction = VoteDirection.Abstain;
    }

    emit Vote(id, direction, voter, uint112(absVotes));
  }

  function _voteUnsafe(uint256 id, address voter) internal {
    ProposalStruct storage proposal = _proposals[id];
    int112 votes = int112(uint112(IVotes(erc20).getPastVotes(voter, proposal.voteBlock)));
    if ((votes != 0) && IFrabricWhitelistCore(erc20).hasKYC(voter)) {
      _voteUnsafe(voter, id, proposal, votes, votes);
    }
  }

  /**
   * @notice Vote on one or multiple proposals, where all must be active
   * @param ids Array of proposal IDs to vote on
   * @param votes Array of number of votes to cast for each corresponding proposal ID
   */
  function vote(uint256[] memory ids, int112[] memory votes) external override {
    if (ids.length != votes.length) {
      revert DifferentLengths(ids.length, votes.length);
    }

    // Require the caller to be KYCd
    if (!IFrabricWhitelistCore(erc20).hasKYC(msg.sender)) {
      revert NotKYC(msg.sender);
    }

    for (uint256 i = 0; i < ids.length; i++) {
      ProposalStruct storage proposal = activeProposal(ids[i]);
      int112 actualVotes = int112(uint112(IVotes(erc20).getPastVotes(msg.sender, proposal.voteBlock)));
      if (actualVotes == 0) {
        return;
      }

      // Since Solidity arrays are bounds checked, this will simply error if votes
      // is too short. If it's too long, it ignores the extras, and the actually processed
      // data doesn't suffer from any mutability
      int112 votesI = votes[i];

      // If they're abstaining, don't check if they have enough votes
      // 0 will be less than (or equal to) whatever amount they do have
      int112 absVotes;
      if (votesI == 0) {
        absVotes = 0;
      } else {
        absVotes = votesI > 0 ? votesI : -votesI;
        // If they're voting with more votes then they actually have, correct votes
        // Also allows UIs to simply vote with type(int112).max
        if (absVotes > actualVotes) {
          // votesI / absVotes will return 1 or -1, representing the vote direction
          votesI = actualVotes * (votesI / absVotes);
          absVotes = actualVotes;
        }
      }

      _voteUnsafe(msg.sender, ids[i], proposal, votesI, absVotes);
    }
  }

  /// @notice Queue a successful proposal to be enacted
  /// @param id ID of proposal to be enacted
  function queueProposal(uint256 id) external override {
    ProposalStruct storage proposal = _proposals[id];

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
    // Since votes is a signed integer, anything greater than 0 signifies more
    // people votes yes than no
    int112 passingVotes = 0;
    if (proposal.supermajority) {
      // Utilize a 66% supermajority requirement
      // With 33% of the votes being against, and 33% of the votes being for,
      // totalVotes will be at 0. In order for a supermajority of 66%, the
      // other 33% must be in excess of this neutral state, hence / 3
      // Doesn't add 1 to handle rounding due to the following if statement
      passingVotes = int112(proposal.totalVotes / 3);
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
    emit ProposalStateChange(id, proposal.state);
  }


  /// @notice Cancel enacting a queued proposal if the voters no longer have sufficient voting power
  /// @param id ID of queued proposal to be cancelled
  /// @param voters Sorted list of voters who voted in favour of proposal `id`
  function cancelProposal(uint256 id, address[] calldata voters) external override {
    // Must be queued. Even if it's completable, if it has yet to be completed, allow this
    ProposalStruct storage proposal = _proposals[id];
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }

    // If the supply has shrunk, this will potentially apply a value greater than the modern 10%
    // If the supply has expanded, this will use the historic vote cap which is smaller than the modern 10%
    // The latter is more accurate and more likely
    int112 tenPercent = int112(uint112(IVotes(erc20).getPastTotalSupply(proposal.voteBlock) / 10));

    int112 newVotes = proposal.votes;
    uint160 prevVoter = 0;
    for (uint i = 0; i < voters.length; i++) {
      address voter = voters[i];
      if (uint160(voter) <= prevVoter) {
        revert UnsortedVoter(voter);
      }
      prevVoter = uint160(voter);

      // If a voter who voted against this proposal (or abstained) is included,
      // whoever wrote JS to handle this has a broken script which isn't working as intended
      int112 voted = proposal.voters[voter];
      if (voted <= 0) {
        revert NotYesVote(id, voter);
      }

      int112 votes = int112(uint112(IERC20(erc20).balanceOf(voter)));
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

    int112 passingVotes = 0;
    if (proposal.supermajority) {
      passingVotes = int112(proposal.totalVotes / 3);
    }

    // If votes are tied, it would've failed queueProposal
    // Fail it here as well (by not using >=)
    if (newVotes > passingVotes) {
      revert ProposalPassed(id, newVotes);
    }

    delete _proposals[id];
    emit ProposalStateChange(id, ProposalState.Cancelled);
  }

  function _completeProposal(uint256 id, uint16 proposalType, bytes calldata data) internal virtual;

  /**
   * @notice Complete a queued proposal `id`
   * @param id ID of the proposal to be completed
   * @param data Arbitrary data to complete this specific proposal with
   * @dev Does not require canonically ordering when executing proposals in case a proposal has invalid actions, halting everything
   */
  function completeProposal(uint256 id, bytes calldata data) external override {
    // Safe against re-entrancy (regarding multiple execution of the same proposal)
    // as long as this block is untouched. While multiple proposals can be executed
    // simultaneously, that should not be an issue
    ProposalStruct storage proposal = _proposals[id];
    // Cheaper than copying the entire thing into memory
    uint16 pType = proposal.pType;
    if (proposal.state != ProposalState.Queued) {
      revert NotQueued(id, proposal.state);
    }
    uint256 end = proposal.stateStartTime + queuePeriod;
    if (block.timestamp < end) {
      revert StillQueued(id, block.timestamp, end);
    }

    // If no one executed this proposal for so long it lapsed, cancel it
    if (block.timestamp > (end + lapsePeriod)) {
      delete _proposals[id];
      emit ProposalStateChange(id, ProposalState.Cancelled);
      return;
    }

    delete _proposals[id];
    // Solely used for getter functionality
    // While we could use it for state checks, we already need to check it's specifically Queued
    passed[id] = true;
    emit ProposalStateChange(id, ProposalState.Executed);

    // Re-entrancy here would do nothing as the proposal has had its state updated
    _completeProposal(id, pType, data);
  }


  /// @notice Lets the proposal creator withdraw an active/queued proposal
  /// @param id ID of proposal to be withdrawn
  function withdrawProposal(uint256 id) external override {
    ProposalStruct storage proposal = _proposals[id];
    // A proposal which didn't pass will pass this check
    // It's not worth checking the timestamp when marking the proposal as Cancelled is more accurate than Active anyways
    if ((proposal.state != ProposalState.Active) && (proposal.state != ProposalState.Queued)) {
      revert InactiveProposal(id);
    }
    // Only allow the proposer to withdraw a proposal.
    if (proposal.creator != msg.sender) {
      revert errors.Unauthorized(msg.sender, proposal.creator);
    }
    delete _proposals[id];
    emit ProposalStateChange(id, ProposalState.Cancelled);
  }

  /// @notice Get the ID of the next proposal to be created
  /// @return uint256 ID of the next proposal to be created
  function nextProposalID() external view override returns (uint256) {
    return _nextProposalID;
  }

  /**
   * @notice Check if a supermajority (circ. supply / 6) is required to approve proposal `id`
   * @param id ID of proposal to be checked
   * @return bool True if proposal `id` requires a supermajority to pass
   * @dev Will only work with proposals which have yet to complete in some form
   * After that, the sole information available onchain is passed, and voteRecord
   * as mappings are not deleted
   */
  function supermajorityRequired(uint256 id) external view override returns (bool) {
    return _proposals[id].supermajority;
  }

  /// @notice Get the vote block (block created at - 1) for proposal `id`
  /// @param id ID of proposal to be checked
  /// @return uint32 Vote block for proposal `id`
  function voteBlock(uint256 id) external view override returns (uint32) {
    return _proposals[id].voteBlock;
  }

  /// @notice Get net number of token votes in approval of proposal `id`
  /// @param id ID of proposal to be checked
  /// @return int112 Number of net token votes in approval of proposal `id`
  function netVotes(uint256 id) public view override returns (int112) {
    return _proposals[id].votes;
  }

  /// @notice Get total number of token votes cast on proposal `id`
  /// @param id ID of proposal to be checked
  /// @return uint112 Number of total votes cast on proposal `id`
  function totalVotes(uint256 id) external view override returns (uint112) {
    return _proposals[id].totalVotes;
  }

  /**
   * @notice Get voting record of address `voter` for proposal `id`
   * @param id ID of the proposal to be checked
   * @param voter Address of the voter to get the record of
   * @return int112 Votes cast by `voter` on proposal `id`
   */
  function voteRecord(uint256 id, address voter) external view override returns (int112) {
    return _proposals[id].voters[voter];
  }
}
