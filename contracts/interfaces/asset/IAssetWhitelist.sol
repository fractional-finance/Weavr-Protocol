// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../modifiers/IPausable.sol";
import "../lists/IGlobalWhitelist.sol";

interface IAssetWhitelist is IGlobalWhitelist, IPausable {
  event ParentWhitelistChanged(address oldParent, address newParent);

  function parentWhitelist() external view returns (address);
}
