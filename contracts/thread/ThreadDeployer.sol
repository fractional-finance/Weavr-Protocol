// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/erc20/ITimelock.sol";

import "../common/Composable.sol";

import "../interfaces/thread/IThreadDeployer.sol";

contract ThreadDeployer is OwnableUpgradeable, Composable, IThreadDeployerSum {
  using SafeERC20 for IERC20;

  address public override crowdfundProxy;
  address public override erc20Beacon;
  address public override threadBeacon;
  address public override auction;
  address public override timelock;

  function initialize(
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon,
    address _auction,
    address _timelock
  ) public override initializer {
    __Ownable_init();

    __Composable_init();
    contractName = keccak256("ThreadDeployer");
    version = 1;
    supportsInterface[type(OwnableUpgradeable).interfaceId] = true;
    supportsInterface[type(IThreadDeployer).interfaceId] = true;

    // This is technically a beacon to keep things consistent
    // That said, it can't actually upgrade itself and has no owner to upgrade it
    // Because of that, it's called a proxy instead of a beacon
    crowdfundProxy = _crowdfundProxy;
    // Beacons which allow code to be changed by the contract itself or its owner
    // Allows Threads upgrading individually
    erc20Beacon = _erc20Beacon;
    threadBeacon = _threadBeacon;

    auction = _auction;
    timelock = _timelock;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {
    contractName = keccak256("ThreadDeployer");
  }

  // Validates a variant and byte data
  function validate(uint256 variant, bytes calldata data) external pure {
    if (variant == 0) {
      abi.decode(data, (address, uint256));
    } else {
      revert UnknownVariant(variant);
    }
  }

  // onlyOwner to ensure all Thread events represent Frabric Threads
  // Takes in a variant in order to support multiple variations easily in the future
  // This could be anything from different Thread architectures to different lockup schemes
  function deploy(
    uint256 _variant,
    address agent,
    string memory name,
    string memory symbol,
    bytes calldata data
  ) external override onlyOwner {
    // Fixes a stack too deep error
    uint256 variant = _variant;
    if (variant != 0) {
      revert UnknownVariant(variant);
    }

    (address tradeToken, uint256 target) = abi.decode(data, (address, uint256));

    // Don't initialize the ERC20 yet
    address erc20 = address(new BeaconProxy(erc20Beacon, bytes("")));

    address thread = address(new BeaconProxy(
      threadBeacon,
      abi.encodeCall(
        IThread.initialize,
        (
          erc20,
          agent,
          msg.sender
        )
      )
    ));

    address parentWhitelist = IDAO(owner()).erc20();

    address crowdfund = address(new BeaconProxy(
      crowdfundProxy,
      abi.encodeCall(
        ICrowdfund.initialize,
        (
          name,
          symbol,
          parentWhitelist,
          agent,
          thread,
          tradeToken,
          target
        )
      )
    ));

    // Initialize the ERC20 now that we can call the Crowdfund contract for decimals
    // Since it needs the decimals of both tokens, yet the ERC20 isn't initialized yet, ensure the decimals are static
    // Prevents anyone from editing the FrabricERC20 and this initialize call without hitting errors during testing
    // Thoroughly documented in Crowdfund
    uint8 decimals = IERC20Metadata(erc20).decimals();
    uint256 threadBaseTokenSupply = ICrowdfund(crowdfund).normalizeRaiseToThread(target);
    // Add 6% on top for the Thread
    uint256 threadTokenSupply = threadBaseTokenSupply * 106 / 100;
    IFrabricERC20(erc20).initialize(name, symbol, threadTokenSupply, false, parentWhitelist, tradeToken, auction);
    if (decimals != IERC20Metadata(erc20).decimals()) {
      revert NonStaticDecimals(decimals, IERC20Metadata(erc20).decimals());
    }

    // Whitelist the Crowdfund and transfer the Thread tokens to it
    IFrabricERC20(erc20).setWhitelisted(crowdfund, keccak256("Crowdfund"));
    IERC20(erc20).safeTransfer(crowdfund, threadBaseTokenSupply);

    // Whitelist Timelock to hold the additional tokens
    // This could be done at a global level given how all Thread tokens sync with this contract
    // That said, not whitelisting it globally avoids FRBC from being sent here accidentally
    IFrabricERC20(erc20).setWhitelisted(timelock, keccak256("Timelock"));

    // Create the lock and transfer the additional tokens to it
    ITimelock(timelock).lock(erc20, 180 days);
    IERC20(erc20).safeTransfer(timelock, threadTokenSupply - threadBaseTokenSupply);

    // Remove ourself from the token's whitelist
    IFrabricERC20(erc20).setWhitelisted(address(this), bytes32(0));

    // Transfer token ownership to the Thread
    OwnableUpgradeable(erc20).transferOwnership(thread);

    emit Thread(variant, agent, tradeToken, erc20, thread, crowdfund);
  }

  // Recover tokens sent here
  function recover(address erc20) public override {
    IERC20(erc20).safeTransfer(owner(), IERC20(erc20).balanceOf(address(this)));
  }

  // Claim a timelock (which sends tokens here) and forward them to the Frabric
  // Purely a helper function
  function claimTimelock(address erc20) external override {
    ITimelock(timelock).claim(erc20);
    recover(erc20);
  }
}
