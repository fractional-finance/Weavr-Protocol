// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

interface IDAO {
  enum ProposalState {
    Active,
    Queued,
    Executed,
    Cancelled
  }

  enum VoteDirection {
    None,
    No,
    Yes
  }

  event NewProposal(uint256 indexed id, uint256 indexed proposalType, address indexed creator, string info);
  event ProposalStateChanged(uint256 indexed id, ProposalState indexed state);
  event Vote(uint256 indexed id, VoteDirection indexed direction, address indexed voter, uint256 votes);

  function erc20() external view returns (address);

  function canPropose() external view returns (bool);
  function proposalActive(uint256 id) external view returns (bool);

  function vote(uint256 id, VoteDirection direction) external;
  function queueProposal(uint256 id) external;
  function cancelProposal(uint256 id, address[] calldata voters) external;
  function completeProposal(uint256 id) external;
  function withdrawProposal(uint256 id) external;

  function proposalVoteBlock(uint256 id) external view returns (uint256);
  function proposalVoteDirection(uint256 id, address voter) external view returns (VoteDirection);
  function proposalVotes(uint256 id) external view returns (int256);
  function proposalTotalVotes(uint256 id) external view returns (uint256);
}

error NotAuthorizedToPropose(address caller);
error InactiveProposal(uint256 id);
error AlreadyVotedInDirection(uint256 id, address voter, IDAO.VoteDirection direction);
error NoVotes(address voter);
error ProposalFailed(uint256 id, int256 votes);
error NotEnoughParticipation(uint256 id, uint256 totalVotes, uint256 required);
error NotQueued(uint256 id, IDAO.ProposalState state);
// Doesn't include what they did vote as it's irrelevant
error NotYesVote(uint256 id, address voter);
error ProposalPassed(uint256 id, int256 votes);
error StillQueued(uint256 id, uint256 time, uint256 queuedUntil);
error AlreadyFinished(uint256 id, IDAO.ProposalState state);
error NotProposalCreator(uint256 id, address creator, address caller);
