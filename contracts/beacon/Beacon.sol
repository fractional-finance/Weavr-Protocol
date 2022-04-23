// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../common/Composable.sol";
import "../interfaces/common/IUpgradeable.sol";

import "../interfaces/beacon/IFrabricBeacon.sol";

contract Beacon is Ownable, Composable, IFrabricBeacon {
  using ERC165Checker for address;

  // Doesn't use immutable so all Beacons have identical code
  bytes32 public override beaconName;
  uint8 public override releaseChannels;

  mapping(address => address) public override implementations;
  // Contained here to provide an authenticated way to deliver upgrade arguments
  // to contracts, instead of just hardcoding them in
  mapping(address => mapping(uint256 => bytes)) public override upgradeDatas;

  constructor(bytes32 _beaconName, uint8 _releaseChannels) Composable("Beacon") Ownable() initializer {
    __Composable_init("Beacon", true);
    supportsInterface[type(Ownable).interfaceId] = true;
    supportsInterface[type(IBeacon).interfaceId] = true;
    supportsInterface[type(IFrabricBeacon).interfaceId] = true;

    beaconName = _beaconName;
    releaseChannels = _releaseChannels;
  }

  function implementation(address instance) public view override returns (address) {
    address impl = implementations[instance];

    // If this contract is tracking a release channel, follow it
    if (uint256(uint160(impl)) < releaseChannels) {
      impl = implementations[impl];
    }

    return impl;
  }

  function upgradeData(address instance, uint256 version) public view override returns (bytes memory) {
    address dataIndex = instance;

    // If this is following a release channel, use its data
    address impl = implementations[dataIndex];
    if (uint256(uint160(impl)) < releaseChannels) {
      dataIndex = impl;
    }

    return upgradeDatas[dataIndex][version];
  }

  function implementation() external view override returns (address) {
    return implementation(msg.sender);
  }

  // virtual so SingleBeacon can lock it down
  function upgrade(
    address instance,
    address impl,
    uint256 version,
    bytes calldata data
  ) public override virtual {
    address old = implementation(instance);

    // Release channel
    if (uint256(uint160(instance)) < releaseChannels) {
      // Only allow the Beacon owner to upgrade these
      if (msg.sender != owner()) {
        revert NotOwner(msg.sender, owner());
      }
      implementations[instance] = impl;

    // Specific impl/other beacon
    } else {
      // The impl for a specific contract can only be upgraded by itself or its owner
      // Relies on short circuiting so even non-owned contracts can call this
      if (!(
        (msg.sender == instance) ||
        ((instance.supportsInterface(type(Ownable).interfaceId)) && (msg.sender == Ownable(instance).owner()))
      )) {
        // Doesn't include the actual upgrade authority due to the ambiguity on who that is
        // Not worth it to try catch on the owner call and actually determine it
        revert NotUpgradeAuthority(msg.sender, instance);
      }

      implementations[instance] = impl;
    }

    // Ensure the new implementation is of the expected type
    address resolved = implementation(instance);
    bytes32 implName = IComposable(resolved).contractName();
    if (
      // This check is decently pointless (especially as we've already called the
      // function in question), yet it at least ensures IComposable
      (!resolved.supportsInterface(type(IComposable).interfaceId)) ||
      (implName != beaconName)
    ) {
      revert DifferentContract(implName, beaconName);
    }

    // Initial code set or moving off release channel
    if ((old != address(0)) && (old != impl)) {
      // We could actually check version is atomically incrementing here, yet it's a pain
      // that won't successfully be feasible to continue if we ever beacon forward
      // and limits recovery options if there ever is an issue with an upgrade path
      // triggerUpgrade does enforce upgrades are only triggered for the relevant version
      if (version < 2) {
        // Technically, >= 2
        revert InvalidVersion(version, 2);
      }

      if (!resolved.supportsInterface(type(IUpgradeable).interfaceId)) {
        revert NotUpgrade(resolved);
      }

      // Validate this upgrade has proper data
      IUpgradeable(resolved).validateUpgrade(version, data);

      // Write the data
      upgradeDatas[instance][version] = data;
    } else if (data.length != 0) {
      revert UpgradeDataForInitial(instance);
    }

    emit Upgrade(instance, impl, version, data);
  }

  function triggerUpgrade(address instance, uint256 version) public override {
    uint256 currVersion = IComposable(instance).version();
    if (currVersion != (version - 1)) {
      revert InvalidVersion(currVersion, version - 1);
    }

    // There is a chance that the contract in question may not have been
    // triggered for old versions, and while we keep the data around, the modern
    // code may not have the ability to handle the old data as needed
    // This must be carefully considered, yet is considered out of scope for
    // this. The fact that upgrade data may resolve differently as code changes
    // is also deemed out of scope

    // Doesn't check for supportsInterface as the version being non-0 and non-max
    // signifies it's intended to be upgraded
    // The fact we have upgrade data with this version means that the code this
    // upgraded to should have an upgrade function ready for it
    IUpgradeable(instance).upgrade(version, upgradeData(instance, version));
  }
}
