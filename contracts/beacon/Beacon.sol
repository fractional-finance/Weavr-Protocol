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
    // Allows a secondary release channel to follow the first (or any other)
    while (uint256(uint160(impl)) < releaseChannels) {
      // Either invalid or release channel 0 which was unset
      if (impl == implementations[impl]) {
        return impl;
      }
      impl = implementations[impl];
    }

    // If this contract's impl is actually another Beacon, hand off to it
    if (impl.supportsInterface(type(IFrabricBeacon).interfaceId)) {
      // Uses IFrabricBeacon instead of IBeacon to get the variant which takes an address
      return IFrabricBeacon(impl).implementation(instance);
    }

    return impl;
  }

  function upgradeData(address instance, uint256 version) public view override returns (bytes memory) {
    address prev = instance;
    address curr = implementations[instance];
    // Perform local resolution to the release channel level
    while (uint256(uint160(curr)) < releaseChannels) {
      prev = curr;
      curr = implementations[curr];
    }

    // prev is now the final release channel tracked. curr is the actual code
    // If the actual code is a Beacon, hand off to their upgradeData
    if (curr.supportsInterface(type(IFrabricBeacon).interfaceId)) {
      return IFrabricBeacon(curr).upgradeData(instance, version);
    }

    // Since the actual code is not a Beacon, use the data specified for the release channel
    // If a contract explicitly upgrades to a specific piece of code, its instance address will be in prev
    return upgradeDatas[prev][version];
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
      if ((msg.sender != instance) && (msg.sender != Ownable(instance).owner())) {
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

    // Doesn't validate version (beyond basic sanity) due to infeasibility
    uint256 min = 2;
    if (old == address(0)) {
      min = 1;
    }

    if (version < min) {
      // Technically, >= min
      revert InvalidVersion(version, min);
    }

    // Considering the lack of validation around data, extensive care must be taken with it
    // We could at least check this version wasn't already written to, yet that'd prevent
    // recovery in the case invalid data did slip in
    upgradeDatas[instance][version] = data;
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
    // this

    // Doesn't check for supportsInterface as the version being non-0 and non-max
    // signifies it's intended to be upgraded
    // The fact we have upgrade data with this version means that the code this
    // upgraded to should have an upgrade function ready for it
    IUpgradeable(instance).upgrade(version, upgradeData(instance, version));
  }
}
