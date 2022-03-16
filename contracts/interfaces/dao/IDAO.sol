// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IDAO {
  event NewProposal(uint256 indexed id, uint256 indexed proposalType, address indexed creator, string info);
  event ProposalStateChanged(uint256 indexed id, uint256 indexed state);
  event Vote(uint256 indexed id, uint256 indexed direction, address indexed voter, uint256 votes);
  event NoVote(uint256 indexed id, address indexed voter, uint256 votes);
  event Abstain(uint256 indexed id, address indexed voter, uint256 votes);

  function erc20() external view returns (address);

  function proposalVoteBlock(uint256 id) external view returns (uint256);
  function proposalVoteDirection(uint256 id, address voter) external view returns (uint256);
  function proposalVotes(uint256 id) external view returns (int256);
  function proposalTotalVotes(uint256 id) external view returns (uint256);
  function proposalActive(uint256 id) external view returns (bool);

  function vote(uint256 id, uint256 direction) external;
  function queueProposal(uint256 id) external;
  function cancelProposal(uint256 id, address[] calldata voters) external;
  function completeProposal(uint256 id) external;
  function withdrawProposal(uint256 id) external;
}
