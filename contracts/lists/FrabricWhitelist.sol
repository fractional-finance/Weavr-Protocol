// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./GlobalWhitelist.sol";

import "../interfaces/lists/IFrabricWhitelist.sol";

abstract contract FrabricWhitelist is Initializable, GlobalWhitelist, IFrabricWhitelist {
  // Whitelist used for the entire Frabric platform
  address public parentWhitelist;

  function _setParentWhitelist(address parentWhitelistAddress) internal {
    emit ParentWhitelistChanged(parentWhitelist, parentWhitelistAddress);
    parentWhitelist = parentWhitelistAddress;
  }

  function __FrabricWhitelist_init(address parentWhitelistAddress) internal onlyInitializing {
    _setParentWhitelist(parentWhitelistAddress);
  }

  function whitelisted(address person) public view override returns (bool) {
    return (
      // Check our own whitelist first
      GlobalWhitelist.whitelisted(person) ||
      // Check the parent whitelist, yet don't trust its own global acceptance policy
      // We have our own for a reason
      ((parentWhitelist != address(0)) && IGlobalWhitelist(parentWhitelist).explicitlyWhitelisted(person))
    );
  }
}
