// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "./Beacon.sol";

// A pointless Beacon which reduces a BeaconProxy to a normal upgradable proxy
// Maintains consistency of using BeaconProxys which may have benefits in the future
// This can be chained with a regular Beacon to become a regular Beacon which BeaconProxys could actually take advantage of
contract SingleBeacon is Beacon {
  constructor() Beacon(1) {}

  function upgrade(address instance, address code) public override {
    if (instance != address(0)) {
      revert UpgradingInstance(instance);
    }
    Beacon.upgrade(instance, code);
  }
}