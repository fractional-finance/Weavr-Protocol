// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../interfaces/modifiers/IGloballyAccepted.sol";

// Controls whether or not *anyone* can participate or only those explicitly specified by a Whitelist
abstract contract GloballyAccepted is IGloballyAccepted {
  bool private _global = false;

  function _globallyAccept() internal {
    _global = true;
    emit GlobalAcceptance();
  }

  function global() public view override returns (bool) {
    return _global;
  }

  // Likely won't be used due to the true/false usage in the whitelist
  // That said, this is good to fill the contract out
  modifier globallyAccepted() {
    require(_global, "GloballyAccepted: Global acceptance hasn't happened yet");
    _;
  }
}
