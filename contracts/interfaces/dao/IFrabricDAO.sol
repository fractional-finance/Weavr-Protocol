// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IDAO.sol";

interface IFrabricDAO is IDAO {
  enum CommonProposalType {
    Paper,
    Upgrade,
    TokenAction,
    ParticipantRemoval
  }

  event UpgradeProposed(
    uint256 indexed id,
    address indexed beacon,
    address indexed instance,
    uint256 version,
    address code,
    bytes data
  );
  event TokenActionProposed(
    uint256 indexed id,
    address indexed token,
    address indexed target,
    bool mint,
    uint256 price,
    uint256 amount
  );
  event ParticipantRemovalProposed(uint256 indexed id, address participant, uint8 fee);

  function commonProposalBit() external view returns (uint16);
  function maxRemovalFee() external view returns (uint8);

  function proposePaper(bytes32 info) external returns (uint256);
  function proposeUpgrade(
    address beacon,
    address instance,
    uint256 version,
    address code,
    bytes calldata data,
    bytes32 info
  ) external returns (uint256);
  function proposeTokenAction(
    address token,
    address target,
    bool mint,
    uint256 price,
    uint256 amount,
    bytes32 info
  ) external returns (uint256);
  function proposeParticipantRemoval(
    address participant,
    uint8 removalFee,
    bytes[] calldata signatures,
    bytes32 info
  ) external returns (uint256);
}

error InvalidRemovalFee(uint8 fee, uint8 max);
error ProposingUpgrade(address beacon, address instance, address code);
error Irremovable(address participant);
error Minting();
error MintingDifferentToken(address specified, address token);
error TargetMalleability(address target, address expected);
error NotRoundAmount(uint256 amount);
