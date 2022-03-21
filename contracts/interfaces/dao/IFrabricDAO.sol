// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "./IDAO.sol";

interface IFrabricDAO is IDAO {
  enum CommonProposalType {
    Paper,
    Upgrade,
    TokenAction
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

  function commonProposalBit() external view returns (uint256);

  function canPropose() external view returns (bool);

  function proposePaper(string calldata info) external returns (uint256);
  function proposeUpgrade(
    string calldata info,
    address beacon,
    address instance,
    address code
  ) external returns (uint256);
  function proposeTokenAction(
    string calldata info,
    address token,
    address target,
    bool mint,
    uint256 price,
    uint256 amount
  ) external returns (uint256);
}
