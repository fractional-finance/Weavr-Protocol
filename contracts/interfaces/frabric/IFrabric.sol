// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IDAO.sol";

interface IFrabric is IDAO {
  event KYCChanged(address indexed oldKYC, address indexed newKYC);

  event ParticipantProposed(uint256 indexed id, address participant, uint256 indexed participantType);
  event ParticipantUpdated(uint256 indexed id, address participant, uint256 indexed participantType);

  event ThreadProposed(uint256 indexed id, address indexed agent, address indexed raiseToken, uint256 target);
  event ThreadProposalProposed(uint256 indexed id, address indexed thread, uint256 proposalType, string info);

  event TokenActionProposed(uint256 indexed id, address indexed token, address indexed target, bool mint, uint256 price, uint256 amount);

  function kyc() external view returns (address);
  function threadDeployer() external view returns (address);
  function guardian(address guardian) external view returns (uint256);

  function proposeParticipant(string calldata info, uint256 participantType, address participant) external returns (uint256);
  function proposeThread(
    string calldata info,
    string memory name,
    string memory symbol,
    address agent,
    address raiseToken,
    uint256 target
  ) external returns (uint256);
  function proposeThreadProposal(string calldata info, address thread, uint256 proposalType, bytes calldata data) external returns (uint256);
  function proposeTokenAction(string calldata info, address token, address target, bool mint, uint256 price, uint256 amount) external returns (uint256);

  function approve(uint256 id, bytes32 kycHash) external;
}
