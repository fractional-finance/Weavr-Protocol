// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThread.sol";

import "../erc20/DividendERC20.sol";

// Uses DividendERC20 for the distribution logic
contract Crowdfund is DividendERC20, ICrowdfund {
  using SafeERC20 for IERC20;

  // Could be gas optimized using 1/2 instead of false/true
  bool private transferAllowed;

  address public whitelist;
  address public agent;
  // Thread isn't needed, just its ERC20
  // This keeps data relative and accessible though, being able to jump to a Thread via its Crowdfund
  // Being able to jump to its token isn't enough as the token doesn't know of the Thread
  address public thread;
  address public token;
  uint256 public target;
  State public state;

  // Alias the total supply to the amount of funds deposited
  // Technically defined as the amount of funds deposited AND outstanding, with
  // no refund claimed nor Thread tokens issued
  function deposited() public view returns (uint256) {
    return totalSupply();
  }

  function initialize(
    string memory name,
    string memory symbol,
    address _whitelist,
    address _agent,
    address _thread,
    address _token,
    uint256 _target
  ) external initializer {
    __ERC20_init(string.concat("Crowdfund ", name), string.concat("CF-", symbol));
    whitelist = _whitelist;
    agent = _agent;
    thread = _thread;
    token = _token;
    if (_target == 0) {
      // Reuse ZeroPrice as the fundraising target is presumably the asset price
      revert ZeroPrice();
    }
    target = _target;
    state = State.Active;
    // This could be packed into the following, yet we'd lose indexing
    emit CrowdfundStarted(agent, thread, token, target);
    emit StateChange(state);

    // Normalize 1 of the raise token to the thread token to ensure normalization won't fail
    normalizeRaiseToThread(1);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // Match the decimals of the underlying ERC20 which this ERC20 maps to
  // If no decimals are specified, assumes 18
  function decimals() public view override returns (uint8) {
    try IERC20Metadata(token).decimals() returns (uint8 result) {
      return result;
    } catch {
      return 18;
    }
  }

  // Frabric ERC20s have 18 decimals. The raise token may have any value (such as 6) or not specify
  // The above function, as documented, handles the raise token's decimals
  // This function normalizes the raise token quantity to the matching thread token quantity
  // If the token in question has more than 18 decimals, this will error
  // The initializer accordingly calls this to confirm normalization won't error at the end of the raise
  // The Frabric could also perform this check, to avoid voting to create a Thread that will fail during deployment
  // Human review is trusted to be sufficient there with this solely being a fallback before funds actually start moving
  function normalizeRaiseToThread(uint256 amount) public view override returns (uint256) {
    // This calls Thread's decimals function BUT according to ThreadDeployer, Thread isn't initialized yet
    // Thread is initialized after Crowdfund due to Crowdfund having the amount conversion code
    // Therefore, Thread's decimals function must be static and work without initialization OR ThreadDeployer must be updated
    // To ensure this is never missed, ThreadDeployer checks for decimal accuracy before and after initialization
    // That way, if anyone edits FrabricERC20 and edits its initializer calls without reading the surrounding code, it'll fail, forcing review
    return amount * (10 ** (18 - decimals()));
  }

  // Don't allow Crowdfund tokens to be transferred, yet mint/burn will still call this hook
  // Internal variable to allow transfers which is only set when minting/burning
  // Could also override transfer/transferFrom with reverts
  function _beforeTokenTransfer(address, address, uint256) internal view override {
    if (!transferAllowed) {
      revert CrowdfundTransfer();
    }
  }

  function burnInternal(address depositor, uint256 amount) private {
    transferAllowed = true;
    _burn(depositor, amount);
    transferAllowed = false;
  }

  function deposit(uint256 amount) external {
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    if (amount > (target - deposited())) {
      amount = target - deposited();
    }
    if (amount == 0) {
      revert ZeroAmount();
    }

    if (!IWhitelist(whitelist).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    // Mint before transferring to prevent re-entrancy causing the Crowdfund to exceed its target
    transferAllowed = true;
    _mint(msg.sender, amount);
    transferAllowed = false;

    // Ban fee on transfer tokens as they'll make the Crowdfund target not feasibly reachable
    // This pattern of checking balance change is generally vulnerable to re-entrancy
    // This usage, which solely checks it received the exact amount expected, is not
    // Any transfers != 0 while re-entered will cause this to error
    // Any transfer == 0 will error due to a check above, and wouldn't have any effect anyways
    // If a fee on transfer is toggled mid raise, withdraw will work without issue,
    // unless the target is actually reached, in which case we continue
    // If the governor can't complete the acquisition given the transfer fee, they can refund what's available
    // Rebase tokens also exist, and will also screw this over, yet there's only so much we can do
    // This contract can also be blacklisted and have all its funds frozen
    // Such cases are deemed as incredibly out of scope for discussion here (and elsewhere)
    uint256 balance = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    if ((IERC20(token).balanceOf(address(this)) - balance) != amount) {
      revert FeeOnTransfer(token);
    }
    emit Deposit(msg.sender, amount);
  }

  // Enable withdrawing funds before the target is reached
  function withdraw(uint256 amount) external {
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    if (deposited() == target) {
      // Doesn't include target as it's not pertinent
      revert CrowdfundReached();
    }
    if (amount == 0) {
      revert ZeroAmount();
    }

    burnInternal(msg.sender, amount);

    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdraw(msg.sender, amount);
  }

  // Cancel a Crowdfund before execution starts
  function cancel() external {
    if (msg.sender != agent) {
      revert NotAgent(msg.sender, agent);
    }
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }

    // Set the State to refunding
    state = State.Refunding;
    _distribute(address(this), token, IERC20(token).balanceOf(address(this)));
    emit StateChange(state);
  }

  // Transfer the funds from a Crowdfund to the agent for execution
  function execute() external {
    if (deposited() != target) {
      revert CrowdfundNotReached();
    }
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    state = State.Executing;
    emit StateChange(state);

    IERC20(token).safeTransfer(agent, target);
  }

  // Take a executing Crowdfund which externally failed and return the leftover funds
  function refund(uint256 amount) external {
    if (msg.sender != agent) {
      revert NotAgent(msg.sender, agent);
    }
    if (state != State.Executing) {
      revert InvalidState(state, State.Executing);
    }
    state = State.Refunding;
    emit StateChange(state);

    // Allows the agent to refund 0
    // If this is improper, they should be bond slashed accordingly
    // They should be bond slashed for any refunded amount which is too low
    // Upon arbitration ruling the amount is too low, the agent could step in
    // and issue a new distribution
    if (amount != 0) {
      _distribute(agent, token, amount);
    }
  }

  function finish() external {
    if (msg.sender != agent) {
      revert NotAgent(msg.sender, agent);
    }
    if (state != State.Executing) {
      revert InvalidState(state, State.Executing);
    }
    state = State.Finished;
    emit StateChange(state);
  }

  // Allow users to burn Crowdfund tokens to receive Thread tokens
  function burn(address depositor) external override {
    if (state != State.Finished) {
      revert InvalidState(state, State.Finished);
    }
    uint256 balance = balanceOf(depositor);
    if (balance == 0) {
      revert ZeroAmount();
    }
    burnInternal(depositor, balance);
    IERC20(IThread(thread).erc20()).safeTransfer(depositor, normalizeRaiseToThread(balance));
  }
}
