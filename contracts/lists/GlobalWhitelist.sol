// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/lists/IGlobalWhitelist.sol";
import "../interfaces/modifiers/IGloballyAccepted.sol";
import "./InfoWhitelist.sol";
import "../modifiers/GloballyAccepted.sol";

// Whitelist with the ability for everyone to eventually be considered whitelisted
abstract contract GlobalWhitelist is GloballyAccepted, InfoWhitelist, IGlobalWhitelist {
  function __GlobalWhitelist_init() internal onlyInitializing {
    __GloballyAccepted_init();
  }

  function whitelisted(address person) public view virtual override(IWhitelist, InfoWhitelist) returns (bool) {
    return global || InfoWhitelist.whitelisted(person);
  }

  function explicitlyWhitelisted(address person) public view override returns (bool) {
    return InfoWhitelist.whitelisted(person);
  }
}
