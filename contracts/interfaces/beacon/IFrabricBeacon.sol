// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

interface IFrabricBeacon is IBeacon {
  event Upgrade(address indexed instance, address indexed code);
  event BeaconRegistered(address indexed beacon);

  // Amount of release channels
  function releaseChannels() external view returns (uint8);
  // Raw address mapping
  function implementations(address code) external view returns (address);
  // Contracts registered as beacons
  function beacon(address code) external view returns (bool);

  // Implementation resolver for a given address
  function implementation(address instance) external view returns (address);
  // Upgrade to different code/a different beacon
  function upgrade(address instance, address code) external;
  // Register a beacon
  function registerAsBeacon() external;
}
