// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IInitialFrabric.sol";

contract InitialFrabric is FrabricDAO, IInitialFrabricInitializable {
  mapping(address => ParticipantType) public participant;

  // The erc20 is expected to be fully initialized via JS during deployment
  function initialize(
    address _erc20,
    address[] calldata genesis,
    bytes32 genesisMerkle // Unvalidated due to lack of an efficient way to do so
  ) external override initializer {
    __FrabricDAO_init("Frabric Protocol", _erc20, 2 weeks, 100);

    __Composable_init("Frabric", false);
    supportsInterface[type(IInitialFrabric).interfaceId] = true;

    // Simulate a full DAO proposal to add the genesis participants
    uint256 id = _fakeProposal(uint16(FrabricProposalType.Participants), keccak256("Genesis Participants"));
    emit ParticipantsProposal(id, ParticipantType.Genesis, genesisMerkle);
    // Actually add the genesis participants
    for (uint256 i = 0; i < genesis.length; i++) {
      participant[genesis[i]] = ParticipantType.Genesis;
      // Now that this event is here, which it wasn't when the full DAO proposal
      // simulation code was added, said code is decently pointless. That said,
      // it does make ParticipantsProposal complete which may be considered beneficial
      // At the very least, there's something romantic about a DAO's first proposal
      // being the people who are there for its start
      emit ParticipantChange(genesis[i], ParticipantType.Genesis);
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Frabric") initializer {}

  function canPropose(address proposer) public view override(DAO, IDAOCore) returns (bool) {
    return uint256(participant[proposer]) > uint256(ParticipantType.Removed);
  }

  function _completeSpecificProposal(uint256, uint256 _pType) internal pure override {
    revert UnhandledEnumCase("InitialFrabric _completeSpecificProposal", _pType);
  }
}
