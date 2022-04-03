// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IDAO.sol";

interface IFrabricDAO {
  enum CommonProposalType {
    Paper,
    Upgrade,
    TokenAction,
    ParticipantRemoval
  }

  event UpgradeProposed(uint256 indexed id, address indexed beacon, address indexed instance, address code);
  event TokenActionProposed(
    uint256 indexed id,
    address indexed token,
    address indexed target,
    bool mint,
    uint256 price,
    uint256 amount
  );
  event RemovalProposed(uint256 indexed id, address participant);

  function commonProposalBit() external view returns (uint16);

  function proposePaper(string calldata info) external returns (uint256);
  function proposeUpgrade(
    address beacon,
    address instance,
    address code,
    string calldata info
  ) external returns (uint256);
  function proposeTokenAction(
    address token,
    address target,
    bool mint,
    uint256 price,
    uint256 amount,
    string calldata info
  ) external returns (uint256);
}

interface IFrabricDAOSum is IDAOSum, IFrabricDAO {}

error ProposingUpgrade(address beacon, address instance, address code);
error MintingDifferentToken(address specified, address token);
error TargetMalleability(address target, address expected);
error NotRoundAmount(uint256 amount);
