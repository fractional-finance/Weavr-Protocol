// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IInitialFrabric is IFrabricDAO {
  enum FrabricProposalType {
    Participants
  }

  enum ParticipantType {
    Null,
    // Removed is before any other type to allow using > Removed to check validity
    Removed,
    Genesis
  }

  event ParticipantsProposal(
    uint256 indexed id,
    ParticipantType indexed participantType,
    bytes32 participants
  );
  event ParticipantChange(address indexed participant, ParticipantType indexed participantType);

  function participant(address participant) external view returns (ParticipantType);
}

interface IInitialFrabricInitializable is IInitialFrabric {
  function initialize(
    address erc20,
    address[] calldata genesis,
    bytes32 genesisMerkle
  ) external;
}
