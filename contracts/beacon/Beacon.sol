// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/beacon/IBeaconUpgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/beacon/IBeacon.sol";

contract Beacon is OwnableUpgradeable, IBeaconUpgradeable, IBeacon {
  uint256 public releaseChannels;

  mapping(address => address) internal _implementation;

  // This could not have an initializer and instead use a constructor
  // This is a pretty low level building block, yet due to release channel functionality,
  // there may be a reason to upgrade this eventually (user added release channels?)
  // Because of that, Beacons should be deployed as `BeaconProxy`s with their own Beacon
  // That Beacon should just not be a BeaconProxy and be the true low level building block
  function initialize(uint256 _releaseChannels) public initializer {
    __Ownable_init();
    releaseChannels = _releaseChannels;
  }

  constructor() {
    initialize(0);
  }

  function implementation() external view override returns (address) {
    address code = _implementation[msg.sender];
    // If this contract is tracking a release channel, follow it
    if (uint256(uint160(code)) <= releaseChannels) {
      code = _implementation[code];
    }
    return code;
  }

  // virtual so SingleBeacon can lock it down
  function upgrade(address instance, address code) public virtual {
    // Validate the code to be a release channel or contract
    // That contract could still be incredibly invalid yet this will catch basic critical errors
    require((uint256(uint160(code)) <= releaseChannels) || Address.isContract(code), "Beacon: Code isn't a release channel nor contract");

    // Release channel
    if (uint256(uint160(instance)) <= releaseChannels) {
      require(msg.sender == owner(), "Beacon: Only owner can upgrade release channel");
      _implementation[instance] = code;

    // Specific code
    } else {
      // The code for a specific contract can only be upgraded by itself or its owner
      // Relies on short circuiting so even non-owned contracts can call this
      require(
        (msg.sender == instance) || (msg.sender == OwnableUpgradeable(instance).owner()),
        "Beacon: Instance's code is being upgraded by unauthorized contract"
      );

      _implementation[instance] = code;
    }
  }
}
