// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../frabric/IFrabric.sol";

import "../common/IComposable.sol";

interface IBond is IComposable {
  event Bond(address governor, uint256 amount);
  event Unbond(address governor, uint256 amount);
  event Slash(address governor, uint256 amount);

  function usd() external view returns (address);
  function bondToken() external view returns (address);

  function bond(uint256 amount) external;
  function unbond(address bonder, uint256 amount) external;
  function slash(address bonder, uint256 amount) external;

  function recover(address token) external;
}

interface IBondInitializable is IBond {
  function initialize(address usd, address bond) external;
}

error BondTransfer();
error NotActiveGovernor(address governor, IFrabric.GovernorStatus status);
// Obvious, yet tells people the exact address to look for avoiding the need to
// then pull it up to double check it
error RecoveringBond(address bond);
