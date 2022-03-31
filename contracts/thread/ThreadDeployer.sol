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

import "../interfaces/frabric/IFrabric.sol";

import "../interfaces/thread/IThreadDeployer.sol";

contract ThreadDeployer is OwnableUpgradeable, IThreadDeployer {
  using SafeERC20 for IERC20;

  address public override crowdfundProxy;
  address public override erc20Beacon;
  address public override threadBeacon;
  address public override auction;

  mapping(address => uint256) public override lockup;

  function initialize(
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon,
    address _auction
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

    auction = _auction;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

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
    uint256 variant,
    address agent,
    string memory name,
    string memory symbol,
    bytes calldata data
  ) external override onlyOwner {
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

    address parentWhitelist = IFrabric(owner()).erc20();

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
    // This allows the Frabric to recover tokens sent to this address by mistake in theory,
    // yet in reality this should never matter
    // If the lockup does exist, the erc20 is interpreted as a Thread (which is guaranteed
    // as we deployed it and set a lockup for it). If it has upgrades enabled, the
    // timelock is automatically voided to prevent the contract from upgrading and
    // clawing back the tokens
    if (!((block.timestamp >= lockup[erc20]) || (IThread(erc20).upgradesEnabled() != 0))) {
      revert TimelockNotExpired(erc20, block.timestamp, lockup[erc20]);
    }
    // Transfer the locked tokens to the Frabric
    IERC20(erc20).safeTransfer(owner(), IERC20(erc20).balanceOf(address(this)));
  }
}
