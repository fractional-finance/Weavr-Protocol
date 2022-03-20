// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../dao/IFrabricDAO.sol";

interface IFrabric is IFrabricDAO {
  event KYCChanged(address indexed oldKYC, address indexed newKYC);

  event ParticipantProposed(uint256 indexed id, address indexed participant, uint256 indexed participantType);
  event ParticipantUpdated(uint256 indexed id, address indexed participant, uint256 indexed participantType);

  event RemoveBondProposed(uint256 indexed id, address indexed participant, bool indexed slash, uint256 amount);
  event ThreadProposed(uint256 indexed id, address indexed agent, address indexed raiseToken, uint256 target);
  event ThreadProposalProposed(uint256 indexed id, address indexed thread, uint256 indexed proposalType, string info);

  enum GovernorStatus {
    Null,
    Unverified, // Proposed and elected, yet hasn't gone through KYC
    Active,
    Removed
  }

  function kyc() external view returns (address);
  function bond() external view returns (address);
  function threadDeployer() external view returns (address);
  function governor(address governor) external view returns (GovernorStatus);

  function initialize(address _erc20, address _kyc, address _bond, address _threadDeployer) external;

  function proposeParticipant(string calldata info, uint256 participantType, address participant) external returns (uint256);
  function proposeRemoveBond(string calldata info, address governor, bool slash, uint256 amount) external returns (uint256);
  function proposeThread(
    string calldata info,
    string memory name,
    string memory symbol,
    address agent,
    address raiseToken,
    uint256 target
  ) external returns (uint256);
  function proposeThreadProposal(string calldata info, address thread, uint256 proposalType, bytes calldata data) external returns (uint256);

  function approve(uint256 id, bytes32 kycHash) external;
}
