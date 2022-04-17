// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

// Only commit to a fraction of the DAO API at this time
// Voting/cancellation/queueing may undergo significant changes in the future
interface IDAOCore is IComposable {
  enum ProposalState {
    Active,
    Queued,
    Executed,
    Cancelled
  }

  event NewProposal(uint256 indexed id, uint256 indexed proposalType, address indexed creator, bytes32 info);
  event ProposalStateChanged(uint256 indexed id, ProposalState indexed state);

  function erc20() external view returns (address);
  function votingPeriod() external view returns (uint64);
  function passed(uint256 id) external view returns (bool);

  function canPropose(address proposer) external view returns (bool);
  function proposalActive(uint256 id) external view returns (bool);

  function completeProposal(uint256 id) external;
  function withdrawProposal(uint256 id) external;
}

interface IDAO is IDAOCore {
  // Solely used to provide indexing based on how people voted
  // Actual voting uses a signed integer at this time
  enum VoteDirection {
    Abstain,
    No,
    Yes
  }

  event Vote(uint256 indexed id, VoteDirection indexed direction, address indexed voter, uint128 votes);

  function queuePeriod() external view returns (uint64);
  function requiredParticipation() external view returns (uint128);

  function vote(uint256[] calldata id, int128[] calldata votes) external;
  function queueProposal(uint256 id) external;
  function cancelProposal(uint256 id, address[] calldata voters) external;

  // Will only work for proposals pre-finalization
  function proposalVoteBlock(uint256 id) external view returns (uint64);
  function proposalVotes(uint256 id) external view returns (int128);
  function proposalTotalVotes(uint256 id) external view returns (uint128);

  // Will work even with finalized proposals (cancelled/completed)
  function proposalVote(uint256 id, address voter) external view returns (int128);
}

error NotAuthorizedToPropose(address caller);
error InactiveProposal(uint256 id);
error ActiveProposal(uint256 id, uint256 time, uint256 endTime);
error ProposalFailed(uint256 id, int256 votes);
error NotEnoughParticipation(uint256 id, uint256 totalVotes, uint256 required);
error NotQueued(uint256 id, IDAO.ProposalState state);
// Doesn't include what they did vote as it's irrelevant
error NotYesVote(uint256 id, address voter);
error UnsortedVoter(address voter);
error ProposalPassed(uint256 id, int256 votes);
error StillQueued(uint256 id, uint256 time, uint256 queuedUntil);
error AlreadyFinished(uint256 id, IDAO.ProposalState state);
error NotProposalCreator(uint256 id, address creator, address caller);
