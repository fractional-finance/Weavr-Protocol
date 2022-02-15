// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../interfaces/thread/ICrowdfund.sol";

// TODO also resolve the fee on transfer/rebase commentary from the DEX here
contract Crowdfund is ICrowdfund, ERC20Upgradeable {
  using SafeERC20 for IERC20;

  // Could be gas optimized using 1/2 instead of false/true
  bool private transferAllowed;

  enum State {
    Active,
    Cancelled,
    Executing,
    Refunding,
    Finished
  }

  address public agent;
  address public thread;
  address public token;
  uint256 public target;
  State private _state;
  uint256 public refunded;

  function state() external view returns (uint256) {
    return uint256(_state);
  }

  // Alias the total supply to the amount of funds deposited
  // Technically defined as the amount of funds deposited AND outstanding, with no refund claimed nor Thread tokens issued
  function deposited() public view returns (uint256) {
    return totalSupply();
  }

  function initialize(string memory name, string memory symbol, address _agent, address _thread, address _token, uint256 _target) external initializer {
    __ERC20_init(name, symbol);
    agent = _agent;
    thread = _thread;
    token = _token;
    require(_target != 0, "Crowdfund: Fundraising target is 0");
    target = _target;
    _state = State.Active;
    // This could be packed into the following, yet we'd lose indexing
    emit CrowdfundStarted(agent, thread, token, target);
    emit StateChange(uint256(_state), bytes(""));
  }

  // Match the decimals of the underlying ERC20 which this ERC20 maps to
  function decimals() public view override returns (uint8) {
    try IERC20Metadata(token).decimals() returns (uint8 result) {
      return result;
    } catch {
      return 18;
    }
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
    require(_state == State.Active, "Crowdfund: Crowdfund isn't active");
    if (amount > (target - deposited())) {
      amount = target - deposited();
    }
    require(amount != 0, "Crowdfund: Amount is 0");

    // Mint before transferring to prevent re-entrancy causing the Crowdfund to exceed its target
    transferAllowed = true;
    _mint(msg.sender, amount);
    transferAllowed = false;

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    emit Deposit(msg.sender, amount);
  }

  // Enable withdrawing funds before the target is reached
  function withdraw(uint256 amount) external {
    require(_state == State.Active, "Crowdfund: Crowdfund isn't active");
    require(deposited() != target, "Crowdfund: Crowdfund reached target");
    require(amount != 0, "Crowdfund: Amount is 0");

    burnInternal(msg.sender, amount);

    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdraw(msg.sender, amount);
  }

  // Cancel a Crowdfund before execution starts
  function cancel() external {
    require(msg.sender == agent, "Crowdfund: Only the agent can cancel");
    require(_state == State.Active, "Crowdfund: Crowdfund isn't active");
    _state = State.Cancelled;
    emit StateChange(uint256(_state), abi.encodePacked(deposited()));
  }

  // Transfer the funds from a Crowdfund to the agent for execution
  function execute() external {
    require(deposited() == target, "Crowdfund: Crowdfund didn't reach target");
    require(_state == State.Active, "Crowdfund: Crowdfund isn't active");
    _state = State.Executing;
    emit StateChange(uint256(_state), bytes(""));

    IERC20(token).safeTransfer(agent, target);
  }

  // Take a executing Crowdfund which externally failed and return the leftover funds
  function refund(uint256 amount) external {
    require(msg.sender == agent, "Crowdfund: Only the agent can trigger a refund");
    require(_state == State.Executing, "Crowdfund: Crowdfund isn't executing");
    _state = State.Refunding;
    emit StateChange(uint256(_state), abi.encodePacked(refunded));

    refunded = amount;
    if (amount != 0) {
      IERC20(token).safeTransferFrom(agent, address(this), refunded);
    }
  }

  function claimRefund(address depositor) external {
    uint256 balance = balanceOf(depositor);
    require(balance != 0, "Crowdfund: Balance is 0");
    uint256 refundAmount;

    if (_state == State.Cancelled) {
      refundAmount = balance;
    } else if (_state == State.Refunding) {
      require(refunded != 0, "Crowdfund: No refund was issued");
      refundAmount = refunded * balance / target;
      require(refundAmount != 0, "Crowdfund: Refund amount is 0");
    } else {
      require(false, "Crowdfund: Not Cancelled nor Refunding");
    }

    burnInternal(depositor, balance);
    IERC20(token).safeTransfer(depositor, refundAmount);
    emit Refund(depositor, refundAmount);
  }

  function finish() external {
    require(msg.sender == agent, "Crowdfund: Only the agent can finish");
    require(_state == State.Executing, "Crowdfund: Crowdfund isn't executing");
    _state = State.Finished;
    emit StateChange(uint256(_state), bytes(""));
  }

  // Allow the Thread to burn Crowdfund tokens so it can safely issue Thread tokens
  function burn(address depositor, uint256 amount) external {
    require(msg.sender == thread, "Crowdfund: Only the thread can burn");
    require(_state == State.Finished, "Crowdfund: Crowdfund isn't finished");
    burnInternal(depositor, amount);
  }
}
