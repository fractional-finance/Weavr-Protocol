// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

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

  function whitelisted(address person) public view virtual override(IWhitelist, GlobalWhitelist) returns (bool) {
    return (
      // Check the parent whitelist
      ((parentWhitelist != address(0)) && IGlobalWhitelist(parentWhitelist).whitelisted(person)) ||
      // Check our own whitelist
      GlobalWhitelist.whitelisted(person)
    );
  }
}
