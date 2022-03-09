// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/thread/IThread.sol";

contract ThreadDeployer is Initializable, OwnableUpgradeable {
  event Thread(address indexed agent, address indexed raiseToken, address crowdfund, address erc20, address thread);

  address public crowdfundProxy;
  address public erc20Beacon;
  address public threadBeacon;

  function initialize(
    address frabric,
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon
  ) public initializer {
    __Ownable_init();
    _transferOwnership(frabric);

    // This could be a TUP chain yet is a BeaconProxy for consistency
    // This beacon is a SingleBeacon with just the one address
    crowdfundProxy = _crowdfundProxy;
    // Beacons which allow code to be changed by the contract itself or its owner
    // Allows Threads upgrading individually
    erc20Beacon = _erc20Beacon;
    threadBeacon = _threadBeacon;
  }

  constructor() {
    initialize(address(0), address(0), address(0), address(0));
  }

  // Only owner to ensure all ThreadCreated events represent Frabric Threads
  function deploy(
    string memory name,
    string memory symbol,
    address parentWhitelist,
    address agent,
    address raiseToken,
    uint256 target
  ) external onlyOwner {
    address crowdfund = address(new BeaconProxy(crowdfundProxy, bytes("")));
    address erc20 = address(new BeaconProxy(erc20Beacon, bytes("")));
    address thread = address(new BeaconProxy(
      threadBeacon,
      abi.encodePacked(
        IThread.initialize.selector,
        crowdfund,
        erc20,
        name,
        symbol,
        parentWhitelist,
        agent,
        raiseToken,
        target
      )
    ));
    emit Thread(agent, raiseToken, crowdfund, erc20, thread);
  }
}
