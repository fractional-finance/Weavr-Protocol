// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import "../modifiers/IPausable.sol";
import "../lists/IGlobalWhitelist.sol";

interface IAssetWhitelist is IGlobalWhitelist, IPausable {
  function setParentWhitelist(address parentWhitelistAddress) external;
  function parentWhitelist() external view returns (address);

  event ParentWhitelistChanged(address oldParent, address newParent);
}
