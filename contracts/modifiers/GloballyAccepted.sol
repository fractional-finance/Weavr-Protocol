// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/modifiers/IGloballyAccepted.sol";

// Controls whether or not *anyone* can participate or only those explicitly specified by a Whitelist
abstract contract GloballyAccepted is Initializable, IGloballyAccepted {
  bool public override global;

  // Should be pointless as-is, yet it's minimally run so fine to leave
  function __GloballyAccepted_init() internal onlyInitializing {
    global = false;
  }

  function _globallyAccept() internal {
    global = true;
    emit GlobalAcceptance();
  }

  // Likely won't be used due to the true/false usage in the whitelist
  // That said, this is good to fill the contract out
  modifier globallyAccepted() {
    require(global, "GloballyAccepted: Global acceptance hasn't happened yet");
    _;
  }
}
