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
    bytes32 genesisMerkle
  ) external override initializer {
    __FrabricDAO_init("Frabric Protocol", _erc20, 2 weeks, 100);

    __Composable_init("Frabric", false);
    supportsInterface[type(IInitialFrabric).interfaceId] = true;

    // Simulate a full DAO proposal to add the genesis participants
    uint256 id = _fakeProposal(uint16(FrabricProposalType.Participants), keccak256("Genesis Participants"));
    emit ParticipantsProposed(id, ParticipantType.Genesis, genesisMerkle);
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
