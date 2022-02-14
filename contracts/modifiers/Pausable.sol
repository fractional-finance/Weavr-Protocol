// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../interfaces/modifiers/IPausable.sol";

abstract contract Pausable is IPausable {
  bool private _paused = false;

  function paused() public view override returns (bool) {
    return _paused;
  }

  modifier whenNotPaused() {
    require(!_paused, "Pausable: Contract is paused");
    _;
  }

  modifier whenPaused() {
    require(_paused, "Pausable: Contract isn't paused");
    _;
  }

  function _pause() internal whenNotPaused {
    _paused = true;
    emit Paused(msg.sender);
  }

  function _unpause() internal whenPaused {
    _paused = false;
    emit Unpaused(msg.sender);
  }
}
