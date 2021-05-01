// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.4;

// Controls whether or not *anyone* can participate or only those explicitly specified by a Whitelist
abstract contract GloballyAccepted {
  event GlobalAcceptance();

  bool private _global = false;

  constructor() {}

  function _globallyAccept() internal {
    _global = true;
    emit GlobalAcceptance();
  }

  function global() public view virtual returns (bool) {
    return _global;
  }

  // Likely won't be used due to the true/false usage in the whitelist
  // That said, this is good to fill the contract out
  modifier globallyAccepted() {
    require(_global);
    _;
  }
}
