// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../interfaces/dao/IDao.sol";

// Provides functions to be used internally to track proposals and votes
abstract contract Dao is IDao {
  struct ProposalMetaData {
    address creator;
    string info;
    mapping(address => bool) voters;
    mapping(address => bool) used;
    uint256 submitted;
    uint256 expires;
    bool completed;
  }
  mapping(uint256 => ProposalMetaData) private _proposals;
  uint256 private _nextProposalId;

  function getProposalCreator(uint256 id) external view override returns (address) {
    return _proposals[id].creator;
  }
  function getProposalInfo(uint256 id) external view override returns (string memory) {
    return _proposals[id].info;
  }
  function getVoteStatus(uint256 id, address voter) external view override returns (bool) {
    return _proposals[id].voters[voter];
  }
  function getTimeSubmitted(uint256 id) external view override returns (uint256) {
    return _proposals[id].submitted;
  }
  function getTimeExpires(uint256 id) external view override returns (uint256) {
    return _proposals[id].expires;
  }
  function getCompleted(uint256 id) public view override returns (bool) {
    return _proposals[id].completed;
  }

  function isProposalActive(uint256 id) public view returns (bool) {
    return (
      // Proposal must actually exist
      (_proposals[id].submitted != 0) &&
      // Has yet to expire
      (block.timestamp < _proposals[id].expires) &&
      // Wasn't completed
      (!_proposals[id].completed)
    );
  }

  modifier activeProposal(uint256 id) {
    require(isProposalActive(id));
    _;
  }

  // Should only be called by a function which attaches coded meaning to this metadata
  function _createProposal(string calldata info, uint256 expires) internal returns (uint256 id) {
    id = _nextProposalId;
    _nextProposalId++;

    ProposalMetaData storage proposal = _proposals[id];
    proposal.creator = msg.sender;
    proposal.info = info;
    proposal.submitted = block.timestamp;
    proposal.expires = expires;

    emit NewProposal(id, proposal.creator, proposal.info);
  }

  function addVote(uint256 id) activeProposal(id) external override {
    // Prevents repeat event emission
    require(!_proposals[id].voters[msg.sender]);
    _proposals[id].voters[msg.sender] = true;
    emit VoteAdded(id, msg.sender);
  }

  function removeVote(uint256 id) activeProposal(id) external override {
    require(_proposals[id].voters[msg.sender]);
    _proposals[id].voters[msg.sender] = false;
    emit VoteRemoved(id, msg.sender);
  }

  // Should only be called by something which acts on the coded meaning of this metadata
  function _completeProposal(uint256 id, address[] calldata voters) activeProposal(id) internal {
    ProposalMetaData storage proposal = _proposals[id];
    // Verify all voters actually voted and no repeats were specified
    for (uint i = 0; i < voters.length; i++) {
      require(proposal.voters[voters[i]]);
      require(!proposal.used[voters[i]]);
      proposal.used[voters[i]] = true;
    }
    proposal.completed = true;
    emit ProposalCompleted(id);
  }

  // Enables withdrawing a proposal
  function withdrawProposal(uint256 id) activeProposal(id) external override {
    // Only allow the proposer to withdraw a proposal.
    require(_proposals[id].creator == msg.sender);
    // Could also set completed to true; this is more accurate as completed suggests passed.
    // activeProposal will still catch this.
    _proposals[id].expires = 0;
    emit ProposalWithdrawn(id);
  }
}
