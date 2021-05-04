// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";

import "../interfaces/lists/IAssetWhitelist.sol";
import "./GlobalWhitelist.sol";

contract AssetWhitelist is IAssetWhitelist, GlobalWhitelist, Pausable {
  // Whitelist used for the entire Frabric platform
  IGlobalWhitelist private _parentWhitelist;

  function _setParentWhitelist(address parentWhitelistAddress) internal {
    emit ParentWhitelistChanged(address(_parentWhitelist), parentWhitelistAddress);
    _parentWhitelist = IGlobalWhitelist(parentWhitelistAddress);
  }

  constructor(address parentWhitelistAddress) GlobalWhitelist() {
    _setParentWhitelist(parentWhitelistAddress);
  }

  function setParentWhitelist(address parentWhitelistAddress) external override onlyOwner {
    _setParentWhitelist(parentWhitelistAddress);
  }

  function parentWhitelist() external view override returns (address) {
    return address(_parentWhitelist);
  }

  function paused() public view override(IPausable, Pausable) returns (bool) {
    return Pausable.paused();
  }

  function pause() external override onlyOwner {
    _pause();
  }

  function unpause() external override onlyOwner {
    _unpause();
  }

  function whitelisted(address person) public view override(IWhitelist, GlobalWhitelist) returns (bool) {
    return (!paused()) && (
      // Check our own whitelist first
      GlobalWhitelist.whitelisted(person) ||
      // Check the parent whitelist, yet don't trust its own global acceptance policy
      // We have our own for a reason
      _parentWhitelist.explicitlyWhitelisted(person)
    );
  }
}
