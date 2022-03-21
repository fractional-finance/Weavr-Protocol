// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThread.sol";

// TODO also resolve the fee on transfer/rebase commentary from the DEX here
contract Crowdfund is ERC20Upgradeable, ICrowdfund {
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
  uint256 public refunded;

  // Alias the total supply to the amount of funds deposited
  // Technically defined as the amount of funds deposited AND outstanding, with no refund claimed nor Thread tokens issued
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
    __ERC20_init(string(abi.encodePacked("Crowdfund ", name)), string(abi.encodePacked("CF-", symbol)));
    whitelist = _whitelist;
    agent = _agent;
    thread = _thread;
    token = _token;
    require(_target != 0, "Crowdfund: Fundraising target is 0");
    target = _target;
    state = State.Active;
    // This could be packed into the following, yet we'd lose indexing
    emit CrowdfundStarted(agent, thread, token, target);
    emit StateChange(state, bytes(""));

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
    require(transferAllowed, "Crowdfund: Token transfers are not allowed");
  }

  function burnInternal(address depositor, uint256 amount) private {
    transferAllowed = true;
    _burn(depositor, amount);
    transferAllowed = false;
  }

  function deposit(uint256 amount) external {
    require(state == State.Active, "Crowdfund: Crowdfund isn't active");
    if (amount > (target - deposited())) {
      amount = target - deposited();
    }
    require(amount != 0, "Crowdfund: Amount is 0");

    require(IWhitelist(whitelist).whitelisted(msg.sender));

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
    uint256 balance = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    if ((IERC20(token).balanceOf(address(this)) - balance) != amount) {
      require(false, "Crowdfund: Fee on transfer tokens are not supported");
    }
    emit Deposit(msg.sender, amount);
  }

  // Enable withdrawing funds before the target is reached
  function withdraw(uint256 amount) external {
    require(state == State.Active, "Crowdfund: Crowdfund isn't active");
    require(deposited() != target, "Crowdfund: Crowdfund reached target");
    require(amount != 0, "Crowdfund: Amount is 0");

    burnInternal(msg.sender, amount);

    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdraw(msg.sender, amount);
  }

  // Cancel a Crowdfund before execution starts
  function cancel() external {
    require(msg.sender == agent, "Crowdfund: Only the agent can cancel");
    require(state == State.Active, "Crowdfund: Crowdfund isn't active");
    state = State.Cancelled;
    emit StateChange(state, abi.encodePacked(deposited()));
  }

  // Transfer the funds from a Crowdfund to the agent for execution
  function execute() external {
    require(deposited() == target, "Crowdfund: Crowdfund didn't reach target");
    require(state == State.Active, "Crowdfund: Crowdfund isn't active");
    state = State.Executing;
    emit StateChange(state, bytes(""));

    IERC20(token).safeTransfer(agent, target);
  }

  // Take a executing Crowdfund which externally failed and return the leftover funds
  function refund(uint256 amount) external {
    require(msg.sender == agent, "Crowdfund: Only the agent can trigger a refund");
    require(state == State.Executing, "Crowdfund: Crowdfund isn't executing");
    state = State.Refunding;
    emit StateChange(state, abi.encodePacked(refunded));

    refunded = amount;
    if (amount != 0) {
      IERC20(token).safeTransferFrom(agent, address(this), refunded);
    }
  }

  function claimRefund(address depositor) external {
    uint256 balance = balanceOf(depositor);
    require(balance != 0, "Crowdfund: Balance is 0");
    uint256 refundAmount;

    if (state == State.Cancelled) {
      refundAmount = balance;
    } else if (state == State.Refunding) {
      require(refunded != 0, "Crowdfund: No refund was issued");
      refundAmount = refunded * balance / target;
      require(refundAmount != 0, "Crowdfund: Refund amount is 0");
    } else {
      require(false, "Crowdfund: Not Cancelled nor Refunding");
    }

    // If for some reason, we move to an ERC777, re-entrancy may be possible here
    // with the balance at the start of the transaction.
    // burn will throw on the second execution however, making this irrelevant
    burnInternal(depositor, balance);
    IERC20(token).safeTransfer(depositor, refundAmount);
    emit Refund(depositor, refundAmount);
  }

  function finish() external {
    require(msg.sender == agent, "Crowdfund: Only the agent can finish");
    require(state == State.Executing, "Crowdfund: Crowdfund isn't executing");
    state = State.Finished;
    emit StateChange(state, bytes(""));
  }

  // Allow users to burn Crowdfund tokens to receive Thread tokens
  // This is shared with Thread
  function burn(address depositor) external override {
    require(state == State.Finished, "Crowdfund: Crowdfund isn't finished");
    uint256 balance = balanceOf(depositor);
    require(balance != 0, "Crowdfund: Balance is 0");
    burnInternal(depositor, balance);
    IERC20(IThread(thread).erc20()).safeTransfer(depositor, normalizeRaiseToThread(balance));
  }
}
