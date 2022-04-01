// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";

// Whitelist which tracks a parent (if set), whitelists with KYC hashes instead of booleans, and can be disabled someday
abstract contract FrabricWhitelist is Initializable, Composable, IFrabricWhitelistSum {
  bool public override global;
  // Whitelist used for the entire Frabric platform
  address public override parentWhitelist;
  // Intended to point to a hash of the whitelisted party's personal info
  mapping(address => bytes32) public override info;

  function _setParentWhitelist(address parent) internal {
    emit ParentWhitelistChange(parentWhitelist, parent);
    parentWhitelist = parent;
  }

  function __FrabricWhitelist_init(address parent) internal onlyInitializing {
    supportsInterface[type(IFrabricWhitelist).interfaceId] = true;
    _setParentWhitelist(parent);
  }

  // Set dataHash of 0x0 to remove from whitelist
  function _setWhitelisted(address person, bytes32 dataHash) internal {
    // If they've already been set with this data hash, return
    if (info[person] == dataHash) {
      return;
    }
    emit WhitelistUpdate(person, info[person], dataHash);
    info[person] = dataHash;
  }

  function whitelisted(address person) public view virtual override returns (bool) {
    return (
      // Check the parent whitelist (actually relevant check most of the time)
      ((parentWhitelist != address(0)) && IFrabricWhitelist(parentWhitelist).whitelisted(person)) ||
      // Global or explicitly whitelisted
      global || (info[person] != bytes32(0))
    );
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return info[person] != bytes32(0);
  }
}
