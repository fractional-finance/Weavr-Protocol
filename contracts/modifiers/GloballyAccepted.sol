// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "../interfaces/modifiers/IGloballyAccepted.sol";

// Controls whether or not *anyone* can participate or only those explicitly specified by a Whitelist
abstract contract GloballyAccepted is IGloballyAccepted {
  bool public override global;

  function _globallyAccept() internal {
    global = true;
    emit GlobalAcceptance();
  }
}
