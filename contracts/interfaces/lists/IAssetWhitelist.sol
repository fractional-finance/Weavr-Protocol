// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";
import "../modifiers/IPausable.sol";
import "./IGlobalWhitelist.sol";

interface IAssetWhitelist is IGlobalWhitelist, IPausable {
  function setParentWhitelist(address parentWhitelistAddress) external;
  function parentWhitelist() external view returns (address);

  event ParentWhitelistChanged(address oldParent, address newParent);
}
