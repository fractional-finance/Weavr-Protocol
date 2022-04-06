// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Using a draft contract isn't great, as is using EIP712 which is technically still under "Review"
// EIP712 was created over 4 years ago and has undegone multiple versions since
// Metamask supports multiple various versions of EIP712 and is committed to maintaing "v3" and "v4" support
// The only distinction between the two is the support for arrays/structs in structs, which aren't used by this contract
// Therefore, this usage is fine, now and in the long-term, as long as one of those two versions is indefinitely supported
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

import "../interfaces/frabric/IBond.sol";
import "../interfaces/thread/IThreadDeployer.sol";
import "../interfaces/thread/IThread.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IInitialFrabric.sol";

contract InitialFrabric is EIP712Upgradeable, FrabricDAO, IInitialFrabricInitializable {
  mapping(address => ParticipantType) public participant;

  // The erc20 is expected to be fully initialized via JS during deployment
  function initialize(
    address _erc20,
    address[] calldata genesis,
    bytes32 genesisMerkle
  ) external override initializer {
    __EIP712_init("Frabric Protocol", "1");
    __FrabricDAO_init(_erc20, 2 weeks);

    __Composable_init("Frabric", false);
    supportsInterface[type(IInitialFrabric).interfaceId] = true;

    // Simulate a full DAO proposal to add the genesis participants
    emit ParticipantsProposed(_nextProposalID, ParticipantType.Genesis, genesisMerkle);
    emit NewProposal(_nextProposalID, uint256(FrabricProposalType.Participants), address(0), "Genesis Participants");
    emit ProposalStateChanged(_nextProposalID, ProposalState.Active);
    emit ProposalStateChanged(_nextProposalID, ProposalState.Queued);
    emit ProposalStateChanged(_nextProposalID, ProposalState.Executed);
    // Update the proposal ID to ensure a lack of collision with the first actual DAO proposal
    _nextProposalID++;
    // Actually add the genesis participants
    for (uint256 i = 0; i < genesis.length; i++) {
      participant[genesis[i]] = ParticipantType.Genesis;
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Frabric") initializer {}

  function canPropose() public view override(DAO, IDAOCore) returns (bool) {
    return uint256(participant[msg.sender]) > uint256(ParticipantType.Removed);
  }

  function _completeSpecificProposal(uint256, uint256 _pType) internal pure override {
    revert UnhandledEnumCase("InitialFrabric _completeSpecificProposal", _pType);
  }
}
