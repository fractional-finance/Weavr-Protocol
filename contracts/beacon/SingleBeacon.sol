// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "./Beacon.sol";

contract SingleBeacon is Beacon {
  constructor(uint8 _releaseChannels) Beacon(_releaseChannels) {}

  function upgrade(address instance, address code) public override {
    require(instance == address(0), "SingleBeacon: Can only upgrade the release channel");
    Beacon.upgrade(instance, code);
  }
}
