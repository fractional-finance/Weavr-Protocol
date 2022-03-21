// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThreadDeployer.sol";

contract ThreadDeployer is Initializable, OwnableUpgradeable, IThreadDeployer {
  using SafeERC20 for IERC20;

  address public override crowdfundProxy;
  address public override erc20Beacon;
  address public override threadBeacon;

  mapping(address => uint256) public override lockup;

  function initialize(
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon
  ) public override initializer {
    __Ownable_init();

    // This is technically a beacon to keep things consistent
    // That said, it can't actually upgrade itself and has no owner to upgrade it
    // Because of that, it's called a proxy instead of a beacon
    crowdfundProxy = _crowdfundProxy;
    // Beacons which allow code to be changed by the contract itself or its owner
    // Allows Threads upgrading individually
    erc20Beacon = _erc20Beacon;
    threadBeacon = _threadBeacon;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // onlyOwner to ensure all Thread events represent Frabric Threads
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
    // Prevents anyone from editing the FrabricERC20 and this initialize call without hitting errors during testing
    // Thoroughly documented in Crowdfund
    uint256 decimals = IERC20Metadata(erc20).decimals();
    uint256 threadBaseTokenSupply = ICrowdfund(crowdfund).normalizeRaiseToThread(target);
    // Add 6% on top for the Thread
    uint256 threadTokenSupply = threadBaseTokenSupply * 106 / 100;
    IFrabricERC20(erc20).initialize(name, symbol, threadTokenSupply, false, parentWhitelist, tradeToken);
    require(decimals == IERC20Metadata(erc20).decimals(), "ThreadDeployer: ERC20 changed decimals on initialization");

    // Whitelist the Crowdfund to hold the Thread tokens
    IFrabricERC20(erc20).setWhitelisted(crowdfund, keccak256("Crowdfund"));

    // Transfer token ownership to the Thread
    OwnableUpgradeable(erc20).transferOwnership(thread);

    // Transfer the Thread token to the Crowdfund
    IERC20(erc20).safeTransfer(crowdfund, threadBaseTokenSupply);

    // Set a lockup for the Thread's token
    lockup[erc20] = block.timestamp + (4 weeks);

    emit Thread(agent, tradeToken, erc20, thread, crowdfund);
  }

  // Claim locked tokens
  function claim(address erc20) external {
    // If this ERC20 never had a lockup, this will automatically clear
    // This allows the Frabric to recover tokens sent to this address by mistake in theory, yet in reality should never matter
    require(block.timestamp >= lockup[erc20], "ThreadDeployer: Lockup has yet to expire");
    // Transfer the 6% to the Frabric
    IERC20(erc20).safeTransfer(owner(), IERC20(erc20).balanceOf(address(this)));
  }
}
