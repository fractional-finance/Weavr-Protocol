// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";

// Whitelist which tracks a parent (if set), whitelists with KYC hashes instead of booleans, and can be disabled someday
abstract contract FrabricWhitelist is Initializable, Composable, IFrabricWhitelistSum {
  using ERC165Checker for address;

  // This is intended to be settable without an upgrade in the future, yet no path currently will
  // A future upgrade may add a governance-followable path to set it
  bool public override global;
  // Whitelist used for the entire Frabric platform
  address public override parentWhitelist;
  // Intended to point to a hash of the whitelisted party's personal info
  mapping(address => bytes32) public override info;
  // List of people removed from the whitelist
  mapping(address => bool) internal _removed;

  function _setParentWhitelist(address parent) internal {
    if ((parent != address(0)) && (!parent.supportsInterface(type(IFrabricWhitelist).interfaceId))) {
      revert UnsupportedInterface(parent, type(IFrabricWhitelist).interfaceId);
    }

    // Does still emit even if address 0 was changed to address 0
    // Used to signify address 0 as the parent is a conscious decision
    emit ParentWhitelistChange(parentWhitelist, parent);
    parentWhitelist = parent;
  }

  function __FrabricWhitelist_init(address parent) internal onlyInitializing {
    supportsInterface[type(IFrabricWhitelist).interfaceId] = true;
    global = false;
    _setParentWhitelist(parent);
  }

  // Set dataHash of 0x0 to remove from whitelist
  function _setWhitelisted(address person, bytes32 dataHash) internal {
    // If they've already been set with this data hash, return
    if (info[person] == dataHash) {
      return;
    }

    // If they were removed, they're being added back. Error on this case
    // The above if statement allows them to be set to 0 multiple times however
    // They will not be 0 if _setRemoved was called while they are whitelisted locally
    // _setRemoved is only called if they're not whitelisted and a local whitelist
    // will always work to count as whitelisted
    if (removed[person]) {
      revert Removed(person);
    }

    emit WhitelistUpdate(person, info[person], dataHash);
    info[person] = dataHash;

    // Doesn't set removed as it is the responsibility of the caller
  }

  // Removed is automatically set when removed from the whitelist yet also may be
  // triggered by the inheriting contract if they were removed from the parent whitelist
  function _setRemoved(address person) internal {
    removed[person] = true;
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

  function removed(address person) public view virtual override returns (bool) {
    return _removed[person];
  }
}
