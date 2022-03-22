// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/beacon/IFrabricBeacon.sol";

contract Beacon is Ownable, IBeacon, IFrabricBeacon {
  uint8 public immutable override releaseChannels;
  mapping(address => address) public override implementations;
  mapping(address => bool) public override beacon;

  constructor(uint8 _releaseChannels) Ownable() {
    releaseChannels = _releaseChannels;
  }

  function implementation(address instance) public view override returns (address) {
    address code = implementations[instance];
    // If this contract is tracking a release channel, follow it
    // Allow a secondary release channel to follow the first (or any other)
    while (uint256(uint160(code)) < releaseChannels) {
      code = implementations[code];
    }
    // If this contract's code is actually another Beacon, hand off to it
    if (beacon[code]) {
      // Uses IFrabricBeacon instead of IBeacon to get the variant which takes an address
      return IFrabricBeacon(code).implementation(instance);
    }
    return code;
  }

  function implementation() external view override returns (address) {
    return implementation(msg.sender);
  }

  // virtual so SingleBeacon can lock it down
  function upgrade(address instance, address code) public override virtual {
    // Validate the code to be a release channel or contract
    // That contract could still be incredibly invalid yet this will catch basic critical errors
    if ((uint256(uint160(code)) >= releaseChannels) && (!Address.isContract(code))) {
      revert InvalidCode(code);
    }

    // Release channel
    if (uint256(uint160(instance)) < releaseChannels) {
      if (msg.sender != owner()) {
        revert NotOwner(msg.sender, owner());
      }
      implementations[instance] = code;

    // Specific code/other beacon
    } else {
      // The code for a specific contract can only be upgraded by itself or its owner
      // Relies on short circuiting so even non-owned contracts can call this
      if ((msg.sender != instance) && (msg.sender != Ownable(instance).owner())) {
        // Doesn't include the actual upgrade authority due to the ambiguity on who that is
        // Not worth it to try catch on the owner call and actually determine it
        revert NotUpgradeAuthority(msg.sender, instance);
      }

      implementations[instance] = code;
    }

    emit Upgrade(instance, code);
  }

  // EIP-165 could also be used for this purpose
  function registerAsBeacon() external override {
    beacon[msg.sender] = true;
    emit BeaconRegistered(msg.sender);
  }
}
