// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/Errors.sol";
import "../common/IComposable.sol";

// Only commit to a fraction of the DAO API at this time
// Voting/cancellation/queueing may undergo significant changes in the future
interface IDAOCore is IComposable {
  enum ProposalState {
    Null,
    Active,
    Queued,
    Executed,
    Cancelled
  }

  event Proposal(
    uint256 indexed id,
    uint256 indexed proposalType,
    address indexed creator,
    bool supermajority,
    bytes32 info
  );
  event ProposalStateChange(uint256 indexed id, ProposalState indexed state);

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
    Yes,
    No
  }

  event Vote(uint256 indexed id, VoteDirection indexed direction, address indexed voter, uint112 votes);

  function queuePeriod() external view returns (uint64);
  function requiredParticipation() external view returns (uint112);

  function vote(uint256[] calldata id, int112[] calldata votes) external;
  function queueProposal(uint256 id) external;
  function cancelProposal(uint256 id, address[] calldata voters) external;

  function nextProposalID() external view returns (uint256);

  // Will only work for proposals pre-finalization
  function supermajorityRequired(uint256 id) external view returns (bool);
  function voteBlock(uint256 id) external view returns (uint32);
  function netVotes(uint256 id) external view returns (int112);
  function totalVotes(uint256 id) external view returns (uint112);

  // Will work even with finalized proposals (cancelled/completed)
  function voteRecord(uint256 id, address voter) external view returns (int112);
}

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
