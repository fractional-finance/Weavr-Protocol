// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";

// Whitelist which tracks a parent (if set), whitelists with KYC hashes instead of booleans, and can be disabled someday
abstract contract FrabricWhitelist is Composable, IFrabricWhitelist {
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

  uint256[100] private __gap;

  function _setParentWhitelist(address parent) internal {
    if ((parent != address(0)) && (!parent.supportsInterface(type(IWhitelist).interfaceId))) {
      revert UnsupportedInterface(parent, type(IWhitelist).interfaceId);
    }

    // Does still emit even if address 0 was changed to address 0
    // Used to signify address 0 as the parent is a conscious decision
    emit ParentWhitelistChange(parentWhitelist, parent);
    parentWhitelist = parent;
  }

  function __FrabricWhitelist_init(address parent) internal onlyInitializing {
    supportsInterface[type(IWhitelist).interfaceId] = true;
    supportsInterface[type(IFrabricWhitelist).interfaceId] = true;
    global = false;
    _setParentWhitelist(parent);
  }

  function _setWhitelisted(address person, bytes32 dataHash) internal {
    if (dataHash == bytes32(0)) {
      revert WhitelistingWithZero(person);
    }

    // If they've already been set with this data hash, return
    if (info[person] == dataHash) {
      return;
    }

    // If they were removed, they're being added back. Error on this case
    // The above if statement allows them to be set to 0 multiple times however
    // They will not be 0 if _setRemoved was called while they are whitelisted locally
    // _setRemoved is only called if they're not whitelisted and a local whitelist
    // will always work to count as whitelisted
    if (_removed[person]) {
      revert Removed(person);
    }

    emit WhitelistUpdate(person, info[person], dataHash);
    info[person] = dataHash;
  }

  function _setRemoved(address person) internal {
    if (_removed[person]) {
      revert Removed(person);
    }
    _removed[person] = true;

    emit WhitelistUpdate(person, info[person], bytes32(0));
    info[person] = bytes32(0);
  }

  function whitelisted(address person) public view virtual override returns (bool) {
    return (
      // Was never removed
      (!_removed[person]) &&
      // Check the parent whitelist (actually relevant check most of the time)
      ((parentWhitelist != address(0)) && IWhitelist(parentWhitelist).whitelisted(person)) ||
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
