// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.4;

import "../interfaces/lists/IGlobalWhitelist.sol";
import "../interfaces/modifiers/IGloballyAccepted.sol";
import "./InfoWhitelist.sol";
import "../modifiers/GloballyAccepted.sol";

// Whitelist with the ability for everyone to eventually be considered whitelisted
contract GlobalWhitelist is IGlobalWhitelist, InfoWhitelist, IGloballyAccepted, GloballyAccepted {
  function globallyAccept() external override onlyOwner {
    _globallyAccept();
  }

  function global() public view override(IGloballyAccepted, GloballyAccepted) returns (bool) {
    return GloballyAccepted.global();
  }

  function whitelisted(address person) public view virtual override(IWhitelist, InfoWhitelist) returns (bool) {
    return global() || InfoWhitelist.whitelisted(person);
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return InfoWhitelist.whitelisted(person);
  }
}
