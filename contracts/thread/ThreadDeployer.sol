// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThreadDeployer.sol";

contract ThreadDeployer is Initializable, OwnableUpgradeable, IThreadDeployer {
  using SafeERC20 for IERC20;

  address public crowdfundProxy;
  address public erc20Beacon;
  address public threadBeacon;

  function initialize(
    address frabric,
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon
  ) public override initializer {
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

  // Only owner to ensure all Thread events represent Frabric Threads
  function deploy(
    string memory name,
    string memory symbol,
    address parentWhitelist,
    address agent,
    address tradeToken,
    uint256 target
  ) external override onlyOwner {
    // Don't initialize the ERC20 yet
    address erc20 = address(new BeaconProxy(erc20Beacon, bytes("")));

    address thread = address(new BeaconProxy(
      threadBeacon,
      abi.encodeWithSelector(
        IThread.initialize.selector,
        erc20,
        agent,
        msg.sender
      )
    ));

    address crowdfund = address(new BeaconProxy(
      crowdfundProxy,
      abi.encodeWithSelector(
        ICrowdfund.initialize.selector,
        name,
        symbol,
        parentWhitelist,
        agent,
        thread,
        tradeToken,
        target
      )
    ));

    // Initialize the ERC20 now that we can call the Crowdfund contract for decimals
    // Since it needs the decimals of both tokens, yet the ERC20 isn't initialized yet, ensure the decimals are static
    // Prevents anyone from editing the FrabricERC20 and this constructor without hitting errors during testing
    // Thoroughly documented in Crowdfund
    uint256 decimals = IERC20Metadata(erc20).decimals();
    uint256 threadTokenSupply = ICrowdfund(crowdfund).normalizeRaiseToThread(target);
    IFrabricERC20(erc20).initialize(name, symbol, threadTokenSupply, false, parentWhitelist, tradeToken);
    require(decimals == IERC20Metadata(erc20).decimals(), "ThreadDeployer: ERC20 changed decimals on initialization");

    // Transfer the Thread token to the Crowdfund
    IERC20(erc20).safeTransfer(crowdfund, threadTokenSupply);
    // Transfer token ownership to the Thread
    OwnableUpgradeable(erc20).transferOwnership(thread);

    emit Thread(agent, tradeToken, erc20, thread, crowdfund);
  }
}
