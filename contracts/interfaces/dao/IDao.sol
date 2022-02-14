// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IDao {
  enum Vote {
    Abstain,
    No,
    Yes
  }

  event NewProposal(uint256 indexed id, address indexed creator, string info, uint256 start, uint256 end);
  event YesVote(uint256 indexed id, address indexed voter, uint256 votes);
  event NoVote(uint256 indexed id, address indexed voter, uint256 votes);
  event Abstain(uint256 indexed id, address indexed voter, uint256 votes);
  event ProposalQueued(uint256 indexed id);
  event ProposalCancelled(uint256 indexed id);
  event ProposalCompleted(uint256 indexed id);
  event ProposalWithdrawn(uint256 indexed id);

  function isProposalActive(uint256 id) external view returns (bool);

  function getProposalCreator(uint256 id) external view returns (address);
  function getProposalInfo(uint256 id) external view returns (string memory);
  function getVoteStatus(uint256 id, address voter) external view returns (Vote);
  function getTimeSubmitted(uint256 id) external view returns (uint256);
  function getTimeExpires(uint256 id) external view returns (uint256);
  function getTimeQueued(uint256 id) external view returns (uint256);
  function getCancelled(uint256 id) external view returns (bool);
  function getCompleted(uint256 id) external view returns (bool);

  function withdrawProposal(uint256 id) external;
}
