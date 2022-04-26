// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IFrabricERC20, IFrabricERC20Initializable } from "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/thread/IThread.sol";
import "../interfaces/thread/ICrowdfund.sol";
import { ITimelock } from "../interfaces/erc20/ITimelock.sol";

import "../common/Composable.sol";

import "../interfaces/thread/IThreadDeployer.sol";

contract ThreadDeployer is OwnableUpgradeable, Composable, IThreadDeployerInitializable {
  using SafeERC20 for IERC20;

  // 6% fee given to the Frabric
  // Since the below code actually does 100% + 6%, this ends up as 5.66%
  // 1% is distributed per month via the timelock
  uint8 constant public override percentage = 6;

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
  ) external override initializer {
    __Ownable_init();

    __Composable_init("ThreadDeployer", false);
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
  constructor() Composable("ThreadDeployer") initializer {}

  // Validates a variant and byte data
  function validate(uint8 variant, bytes calldata data) external override pure {
    if (variant == 0) {
      abi.decode(data, (address, uint112));
    } else {
      revert UnknownVariant(variant);
    }
  }

  // Dedicated function to resolve stack depth errors
  function deployThread(
    string memory name,
    address erc20,
    bytes32 descriptor,
    address governor,
    address crowdfund
  ) private returns (address) {
    // Prevent participant removals against the following
    address[] memory irremovable = new address[](3);
    irremovable[0] = msg.sender;
    irremovable[1] = timelock;
    irremovable[2] = crowdfund;
    // We could also include the Auction contract here, or an eventual Uniswap pair
    // The first can't be done, as it'll be removed and then transferred its own tokens
    // to be put up for Auction, which will error. The latter isn't present here
    // and may never exist. Beyond the stupidity of attacking core infrastructure,
    // there's no successful game theory incentives to doing it, hence why it's just these

    return address(new BeaconProxy(
      threadBeacon,
      abi.encodeWithSelector(
        IThreadInitializable.initialize.selector,
        name,
        erc20,
        descriptor,
        msg.sender,
        governor,
        irremovable
      )
    ));
  }

  function initERC20(
    address erc20,
    string memory name,
    string memory symbol,
    uint256 threadBaseTokenSupply,
    address parent,
    address tradeToken
  ) private returns (uint256) {
    // Since the Crowdfund needs the decimals of both tokens (raise and Thread),
    // yet the ERC20 isn't initialized yet, ensure the decimals are static
    // Prevents anyone from editing the FrabricERC20 and this initialize call
    // without hitting actual errors during testing
    // Thoroughly documented in Crowdfund
    uint8 decimals = IERC20Metadata(erc20).decimals();

    // Add 6% on top for the Frabric
    uint256 threadTokenSupply = threadBaseTokenSupply * (100 + uint256(percentage)) / 100;

    IFrabricERC20Initializable(erc20).initialize(
      name,
      symbol,
      threadTokenSupply,
      parent,
      tradeToken,
      auction
    );

    if (decimals != IERC20Metadata(erc20).decimals()) {
      revert NonStaticDecimals(decimals, IERC20Metadata(erc20).decimals());
    }

    return threadTokenSupply - threadBaseTokenSupply;
  }

  // onlyOwner to ensure all Thread events represent Frabric Threads
  // Takes in a variant in order to support multiple variations easily in the future
  // This could be anything from different Thread architectures to different lockup schemes
  function deploy(
    // Not an enum so the ThreadDeployer can be upgraded with more without requiring
    // the Frabric to also be upgraded
    // Is an uint8 so this contract can use it as an enum if desired in the future
    uint8 _variant,
    string memory _name,
    string memory _symbol,
    bytes32 _descriptor,
    address _governor,
    bytes calldata data
  ) external override onlyOwner {
    // Fixes stack too deep errors
    uint8 variant = _variant;
    string memory name = _name;
    string memory symbol = _symbol;
    bytes32 descriptor = _descriptor;
    address governor = _governor;

    if (variant != 0) {
      revert UnknownVariant(variant);
    }

    (address tradeToken, uint112 target) = abi.decode(data, (address, uint112));

    // Don't initialize the ERC20/Crowdfund yet
    // It may be advantageous to utilize CREATE2 here, yet probably doesn't matter
    address erc20 = address(new BeaconProxy(erc20Beacon, bytes("")));
    address crowdfund = address(new BeaconProxy(crowdfundProxy, bytes("")));

    // Deploy and initialize the Thread
    address thread = deployThread(name, erc20, descriptor, governor, crowdfund);

    address parent = IDAOCore(msg.sender).erc20();

    // Initialize the Crowdfund
    ICrowdfundInitializable(crowdfund).initialize(
      name,
      symbol,
      parent,
      governor,
      thread,
      tradeToken,
      target
    );

    uint256 threadBaseTokenSupply = ICrowdfund(crowdfund).normalizeRaiseToThread(target);

    // Initialize the ERC20 now that we can call the Crowdfund contract for decimals
    uint256 frabricShare = initERC20(
      erc20,
      name,
      symbol,
      threadBaseTokenSupply,
      parent,
      tradeToken
    );

    // Whitelist the Crowdfund and transfer the Thread tokens to it
    IFrabricERC20(erc20).setWhitelisted(crowdfund, keccak256("Crowdfund"));
    IERC20(erc20).safeTransfer(crowdfund, threadBaseTokenSupply);

    // Whitelist Timelock to hold the additional tokens
    // This could be done at a global level given how all Thread tokens sync with this contract
    // That said, not whitelisting it globally avoids FRBC from being sent here accidentally
    IFrabricERC20(erc20).setWhitelisted(timelock, keccak256("Timelock"));

    // Create the lock and transfer the additional tokens to it
    // Schedule it to release at 1% per month
    ITimelock(timelock).lock(erc20, percentage);
    IERC20(erc20).safeTransfer(timelock, frabricShare);

    // Remove ourself from the token's whitelist
    IFrabricERC20(erc20).remove(address(this), 0);

    // Transfer token ownership to the Thread
    OwnableUpgradeable(erc20).transferOwnership(thread);

    // Doesn't include name/symbol due to stack depth issues
    // descriptor is sufficient to confirm which of the Frabric's events this lines up with,
    // assuming it's unique, which it always should be (though this isn't explicitly confirmed on chain)
    emit Thread(thread, variant, governor, erc20, descriptor);
    emit CrowdfundedThread(thread, tradeToken, crowdfund, target);
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
