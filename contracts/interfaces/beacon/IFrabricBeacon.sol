// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../common/IComposable.sol";

interface IFrabricBeacon is IBeacon, IComposable {
  event Upgrade(address indexed instance, address indexed code, uint256 indexed version, bytes data);

  // Name of the contract this beacon points to
  function beaconName() external view returns (bytes32);

  // Amount of release channels
  function releaseChannels() external view returns (uint8);

  // Raw address mapping. This does not perform resolution
  function implementations(address code) external view returns (address);

  // Raw upgrade data mapping. This does not perform resolution
  function upgradeDatas(address instance, uint256 version) external view returns (bytes memory);

  // Implementation resolver for a given instance
  // IBeacon has an implementation function defined yet it doesn't take an argument
  // as OZ beacons only expect to handle a single implementation address
  function implementation(address instance) external view returns (address);

  // Upgrade data resolution for a given instance
  function upgradeData(address instance, uint256 version) external view returns (bytes memory);

  // Upgrade to different code/forward to a different beacon
  function upgrade(address instance, address code, uint256 version, bytes calldata data) external;

  // Trigger an upgrade for the specified contract
  function triggerUpgrade(address instance, uint256 version) external;
}

// Errors used by Beacon
error InvalidCode(address code);
// Caller may be a bit extra, yet these only cost gas when executed
// The fact wallets try execution before sending transactions should mean this is a non-issue
error NotOwner(address caller, address owner);
error NotUpgradeAuthority(address caller, address instance);
error DifferentContract(bytes32 oldName, bytes32 newName);
error InvalidVersion(uint256 version, uint256 expectedVersion);
error NotUpgrade(address code);

// Errors used by SingleBeacon
// SingleBeacons only allow its singular release channel to be upgraded
error UpgradingInstance(address instance);
