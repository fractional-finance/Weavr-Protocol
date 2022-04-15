// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "./Beacon.sol";

// A pointless Beacon which reduces a BeaconProxy to a normal upgradable proxy
// Maintains consistency of using BeaconProxys which may have benefits in the future
// This can be chained with a regular Beacon to become a regular Beacon which
// BeaconProxys could actually take advantage of
contract SingleBeacon is Beacon {
  constructor(bytes32 beaconName) Beacon(beaconName, 1) {}

  function upgrade(
    address instance,
    address impl,
    uint256 version,
    bytes calldata data
  ) public override {
    if (instance != address(0)) {
      revert UpgradingInstance(instance);
    }
    super.upgrade(instance, impl, version, data);
  }
}
