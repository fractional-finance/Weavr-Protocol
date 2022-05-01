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
  // Current status on the whitelist
  mapping(address => Status) private _status;
  // Height at which people were removed from the whitelist
  mapping(address => uint256) private _removed;
  // Intended to point to a hash of the whitelisted party's KYC info
  // This will NOT resolve to its parent's info if no info is set here
  mapping(address => bytes32) public override kyc;
  mapping(address => uint256) public override kycNonces;

  uint256[100] private __gap;

  function _setGlobal() internal {
    global = true;
    emit GlobalAcceptance();
  }

  function _setParent(address _parent) internal {
    if ((_parent != address(0)) && (!_parent.supportsInterface(type(IFrabricWhitelistCore).interfaceId))) {
      revert UnsupportedInterface(_parent, type(IFrabricWhitelistCore).interfaceId);
    }

    // Does still emit even if address 0 was changed to address 0
    // Used to signify address 0 as the parent is a conscious decision
    emit ParentChange(parent, _parent);
    parent = _parent;
  }

  function __FrabricWhitelist_init(address _parent) internal onlyInitializing {
    supportsInterface[type(IFrabricWhitelistCore).interfaceId] = true;
    supportsInterface[type(IFrabricWhitelist).interfaceId] = true;
    _setParent(_parent);
  }

  function _whitelist(address person) internal {
    if (_status[person] != Status.Null) {
      if (_status[person] == Status.Removed) {
        revert Removed(person);
      }
      revert AlreadyWhitelisted(person);
    }

    _status[person] = Status.Whitelisted;
    emit Whitelisted(person, true);
  }

  function _setKYC(address person, bytes32 hash, uint256 nonce) internal {
    // Make sure this is an actual user
    if (_status[person] == Status.Null) {
      revert NotWhitelisted(person);
    }

    // Make sure this isn't replayed
    if (nonce != kycNonces[person]) {
      revert Replay(nonce, kycNonces[person]);
    }
    kycNonces[person]++;

    // If they were previously solely whitelisted, mark them as KYCd
    if (_status[person] == Status.Whitelisted) {
      _status[person] = Status.KYC;
    }

    // Update the KYC hash
    emit KYCUpdate(person, kyc[person], hash, nonce);
    kyc[person] = hash;
  }

  function _setRemoved(address person) internal {
    if (removed(person)) {
      revert Removed(person);
    }

    _status[person] = Status.Removed;
    _removed[person] = block.number;
    emit Whitelisted(person, false);
  }

  function status(address person) public view override returns (Status) {
    Status res = _status[person];
    if (res == Status.Removed) {
      return res;
    }

    // If we have a parent, get their status
    if (parent != address(0)) {
      // Use a raw call so we get access to the uint8 format instead of the Status format
      (bool success, bytes memory data) = parent.staticcall(
        abi.encodeWithSelector(IFrabricWhitelistCore.status.selector, person)
      );
      if (!success) {
        revert ExternalCallFailed(parent, IFrabricWhitelistCore.status.selector, data);
      }

      // Decode it
      (uint8 parentStatus) = abi.decode(data, (uint8));
      // If the parent expanded their Status enum, convert it into our range to prevent bricking
      // This does still have rules on how the parent can expand yet is better than a complete failure
      if (parentStatus > uint8(type(Status).max)) {
        parentStatus = uint8(type(Status).max);
      }

      // Use whichever status is higher
      if (parentStatus > uint8(res)) {
        return Status(parentStatus);
      }
    }

    return res;
  }

  function whitelisted(address person) public view virtual override returns (bool) {
    return (
      // Was never removed
      (!removed(person)) && (
        // Whitelisted by the parent (actually relevant check most of the time)
        ((parent != address(0)) && IFrabricWhitelistCore(parent).whitelisted(person)) ||
        // Explicitly whitelisted or global
        explicitlyWhitelisted(person) || global
      )
    );
  }

  function hasKYC(address person) external view override returns (bool) {
    return uint8(status(person)) >= uint8(Status.KYC);
  }

  function removed(address person) public view virtual override returns (bool) {
    return _status[person] == Status.Removed;
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return uint8(_status[person]) >= uint8(Status.Whitelisted);
  }

  function removedAt(address person) external view override returns (uint256) {
    return _removed[person];
  }
}
