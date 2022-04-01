// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../common/IComposable.sol";

interface IFrabricBeacon {
  event Upgrade(address indexed instance, address indexed code);
  event BeaconRegistered(address indexed beacon);

  // Amount of release channels
  function releaseChannels() external view returns (uint8);
  // Name of contract this beacon points to
  function beaconName() external view returns (bytes32);
  // Raw address mapping
  function implementations(address code) external view returns (address);

  // Implementation resolver for a given address
  function implementation(address instance) external view returns (address);
  // Upgrade to different code/a different beacon
  function upgrade(address instance, address code) external;
}

interface IFrabricBeaconSum is IBeacon, IComposableSum, IFrabricBeacon {}

// Errors used by Beacon
error InvalidCode(address code);
// Caller may be a bit extra, yet these only cost gas when executed
// The fact wallets try execution before sending transactions should mean this is a non-issue
error NotOwner(address caller, address owner);
error NotUpgradeAuthority(address caller, address instance);
error DifferentContract(bytes32 oldName, bytes32 newName);

// Errors used by SingleBeacon
// SingleBeacons only allow its singular release channel to be upgraded
error UpgradingInstance(address instance);
