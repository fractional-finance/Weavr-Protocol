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
  address public override parent;
  // Intended to point to a hash of the whitelisted party's personal info
  // This will NOT resolve to its parent's info if no info is set here
  mapping(address => bytes32) public override info;
  // List of people removed from the whitelist
  mapping(address => bool) private _removed;

  uint256[100] private __gap;

  function _setGlobal() internal {
    global = true;
    emit GlobalAcceptance();
  }

  function _setParent(address _parent) internal {
    if ((_parent != address(0)) && (!_parent.supportsInterface(type(IWhitelist).interfaceId))) {
      revert UnsupportedInterface(_parent, type(IWhitelist).interfaceId);
    }

    // Does still emit even if address 0 was changed to address 0
    // Used to signify address 0 as the parent is a conscious decision
    emit ParentChange(parent, _parent);
    parent = _parent;
  }

  function __FrabricWhitelist_init(address _parent) internal onlyInitializing {
    supportsInterface[type(IWhitelist).interfaceId] = true;
    supportsInterface[type(IFrabricWhitelist).interfaceId] = true;
    global = false;
    _setParent(_parent);
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

    if (info[person] == bytes32(0)) {
      emit Whitelisted(person, true);
    }

    emit InfoChange(person, info[person], dataHash);
    info[person] = dataHash;
  }

  function _setRemoved(address person) internal {
    if (_removed[person]) {
      revert Removed(person);
    }
    _removed[person] = true;

    emit Whitelisted(person, false);
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return (info[person] != bytes32(0)) && (!_removed[person]);
  }

  function whitelisted(address person) public view virtual override returns (bool) {
    return (
      // Was never removed
      (!_removed[person]) &&
      // Check the parent whitelist (actually relevant check most of the time)
      ((parent != address(0)) && IWhitelist(parent).whitelisted(person)) ||
      // Global or explicitly whitelisted
      global || explicitlyWhitelisted(person)
    );
  }

  function removed(address person) public view virtual override returns (bool) {
    return _removed[person];
  }
}
