// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../common/Composable.sol";

import "../interfaces/beacon/IFrabricBeacon.sol";

contract Beacon is Ownable, Composable, IFrabricBeacon {
  using ERC165Checker for address;

  bytes32 public immutable override beaconName;
  uint8 public immutable override releaseChannels;
  mapping(address => address) public override implementations;

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
      impl = implementations[impl];
    }

    // If this contract's impl is actually another Beacon, hand off to it
    if (impl.supportsInterface(type(IFrabricBeacon).interfaceId)) {
      // Uses IFrabricBeacon instead of IBeacon to get the variant which takes an address
      return IFrabricBeacon(impl).implementation(instance);
    }

    return impl;
  }

  function implementation() external view override returns (address) {
    return implementation(msg.sender);
  }

  // virtual so SingleBeacon can lock it down
  function upgrade(address instance, address impl) public override virtual {
    // Release channel
    if (uint256(uint160(instance)) < releaseChannels) {
      // Only allow the Beacon owner to upgrade these
      if (msg.sender != owner()) {
        revert NotOwner(msg.sender, owner());
      }
      implementations[instance] = impl;

    // Specific code/other beacon
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

    emit Upgrade(instance, impl);

    // Ensure the new implementation is of the expected type
    // This does enforce a bound on code to be IComposable
    // We could check the code supports the IComposable interface here yet this
    // is a sufficiently specific call which would cause an error in the same location
    if (IComposable(implementation(instance)).contractName() != beaconName) {
      revert DifferentContract(IComposable(implementation(instance)).contractName(), beaconName);
    }
  }
}
