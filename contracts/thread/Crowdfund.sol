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

  address public agent;
  address public thread;
  address public token;
  uint256 public target;
  bool public active;
  bool public finished;
  uint256 public refunded;
  bool public success;

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
    require(_target != 0);
    target = _target;
    active = true;
    emit CrowdfundStarted(agent, thread, token, target);
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
    require(transferAllowed);
  }

  function deposit(uint256 amount) external {
    require(active);
    if (amount > (target - deposited())) {
      amount = target - deposited();
    }
    require(amount != 0);

    // Mint before transferring to prevent re-entrancy causing the Crowdfund to exceed its target
    transferAllowed = true;
    _mint(msg.sender, amount);
    transferAllowed = false;

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    emit Deposit(msg.sender, amount);
  }

  // Enable withdrawing funds before the target is reached
  function withdraw(uint256 amount) external {
    require(deposited() != target);
    require(amount != 0);

    transferAllowed = true;
    _burn(msg.sender, amount);
    transferAllowed = false;

    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdraw(msg.sender, amount);
  }

  // Cancel a Crowdfund before it reaches its target
  function cancel() external {
    require(msg.sender == agent);
    require(deposited() < target);
    require(active);
    active = false;
    finished = true;
    emit Cancelled(deposited());
  }

  // Transfer the funds from a Crowdfund to the agent for execution
  function execute() external {
    require(deposited() == target);
    require(active);
    active = false;
    IERC20(token).safeTransfer(agent, target);
    emit Executing();
  }

  // Take a executing Crowdfund which externally failed and return the leftover funds
  function refund(uint256 amount) external {
    require(msg.sender == agent);
    require(!active);
    // Since it's not active, it must have hit target for it to not also be finished
    // Therefore, it wasn't cancelled and this is a valid code path
    require(!finished);
    finished = true;
    refunded = amount;
    if (amount != 0) {
      IERC20(token).safeTransferFrom(agent, address(this), amount);
    }
    emit RefundTriggered(amount);
  }

  function claimRefund(address depositor) external {
    require(refunded != 0);
    uint256 balance = balanceOf(depositor);
    require(balance != 0);
    _burn(depositor, balance);
    uint256 refundAmount = balance * refunded / target;
    IERC20(token).safeTransfer(depositor, refundAmount);
    emit Refund(depositor, refundAmount);
  }

  function finish() external {
    require(msg.sender == agent);
    require(!active);
    require(!finished);
    finished = true;
    success = true;
    emit Finished();
  }

  // Allow the Thread to burn Crowdfund tokens so it can safely issue Thread tokens
  function burn(address depositor, uint256 amount) external {
    require(msg.sender == thread);
    require(success);
    transferAllowed = true;
    _burn(depositor, amount);
    transferAllowed = false;
  }
}
