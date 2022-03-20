// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "./InfoWhitelist.sol";
import "../modifiers/GloballyAccepted.sol";
import "../interfaces/lists/IGlobalWhitelist.sol";

// Whitelist with the ability for everyone to eventually be considered whitelisted
abstract contract GlobalWhitelist is InfoWhitelist, GloballyAccepted, IGlobalWhitelist {
  function __GlobalWhitelist_init() internal onlyInitializing {
    __InfoWhitelist_init();
    __GloballyAccepted_init();
  }

  function whitelisted(address person) public view virtual override(IWhitelist, InfoWhitelist) returns (bool) {
    return global || InfoWhitelist.whitelisted(person);
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return InfoWhitelist.whitelisted(person);
  }
}
