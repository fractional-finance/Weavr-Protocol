// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

interface IDAO {
  struct ProposalMetaData {
    address creator;
    string info;
    mapping(address => bool) voters;
    mapping(address => bool) used;
    uint256 submitted;
    uint256 expires;
    bool completed;
  }

  event NewProposal(uint256 indexed id, address indexed creator, string info);
  event VoteAdded(uint256 indexed id, address indexed voter);
  event VoteRemoved(uint256 indexed id, address indexed voter);
  event ProposalCompleted(uint256 indexed id);
  event ProposalWithdrawn(uint256 indexed id);

  function getProposalCreator(uint256 id) external view returns (address);
  function getProposalInfo(uint256 id) external view returns (string memory);
  function getVoteStatus(uint256 id, address voter) external view returns (bool);
  function getTimeSubmitted(uint256 id) external view returns (uint256);
  function getTimeExpires(uint256 id) external view returns (uint256);
  function getCompleted(uint256 id) external view returns (bool);

  function addVote(uint256 id) external;
  function removeVote(uint256 id) external;
  function withdrawProposal(uint256 id) external;
}
