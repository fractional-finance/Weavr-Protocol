// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IInitialFrabric is IFrabricDAO {
  enum FrabricProposalType {
    Participant
  }

  enum ParticipantType {
    Null,
    // Removed is before any other type to allow using > Removed to check validity
    Removed,
    Genesis
  }

  event ParticipantProposal(
    uint256 indexed id,
    ParticipantType indexed participantType,
    address participant
  );
  event ParticipantChange(ParticipantType indexed participantType, address indexed participant);

  function participant(address participant) external view returns (ParticipantType);
}

interface IInitialFrabricInitializable is IInitialFrabric {
  function initialize(
    address erc20,
    address[] calldata genesis
  ) external;
}
