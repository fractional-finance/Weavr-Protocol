// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThread.sol";

import "../erc20/DistributionERC20.sol";

// Uses DistributionERC20 for the distribution logic
contract Crowdfund is DistributionERC20, ICrowdfundInitializable {
  using SafeERC20 for IERC20;

  // Could be gas optimized using 1/2 instead of false/true
  bool private transferAllowed;

  address public override whitelist;
  address public override governor;
  // Thread isn't needed, just its ERC20
  // This keeps data relative and accessible though, being able to jump to a Thread via its Crowdfund
  // Being able to jump to its token isn't enough as the token doesn't know of the Thread
  ICrowdfund.State public state;
  address public override thread;
  address public override token;
  uint112 public override target;
  uint64 public override lastDepositTime;

  // Amount of tokens which have yet to be converted to Thread tokens
  // Equivalent to the amount of funds deposited and not withdrawn if none have
  // been burnt yet
  function outstanding() public view override returns (uint112) {
    // Safe cast as mintage matches target and target is uint112
    return uint112(totalSupply());
  }

  function initialize(
    string memory name,
    string memory symbol,
    address _whitelist,
    address _governor,
    address _thread,
    address _token,
    uint112 _target
  ) external override initializer returns (uint256) {
    __DistributionERC20_init(
      string(abi.encodePacked("Crowdfund ", name)),
      string(abi.encodePacked("CF-", symbol))
    );

    __Composable_init("Crowdfund", false);
    supportsInterface[type(ICrowdfund).interfaceId] = true;

    whitelist = _whitelist;
    governor = _governor;
    thread = _thread;
    token = _token;
    if (_target == 0) {
      // Reuse ZeroPrice as the fundraising target is presumably the asset price
      revert errors.ZeroPrice();
    }
    target = _target;
    state = State.Active;
    emit StateChange(state);

    // Normalize the target in the raise token to the Thread token to ensure normalization won't fail
    // Also return it, so the ThreadDeployer doesn't have to call this again
    return normalizeRaiseToThread(target);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Crowdfund") initializer {}

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
    // That way, if anyone edits FrabricERC20 and edits its initializer calls without reading the surrounding code,
    // it'll fail, forcing review
    return amount * (10 ** (18 - decimals()));
  }

  // Don't allow Crowdfund tokens to be transferred, yet mint/burn will still call this hook
  // Internal variable to allow transfers which is only set when minting/burning
  // Could also override transfer/transferFrom with reverts
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    super._beforeTokenTransfer(from, to, amount);
    if (!transferAllowed) {
      revert CrowdfundTransfer();
    }
  }

  function _burn(address depositor, uint256 amount) internal override {
    transferAllowed = true;
    super._burn(depositor, amount);
    transferAllowed = false;
  }

  function deposit(uint112 amount) external override returns (uint112) {
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    if (amount > (target - outstanding())) {
      amount = target - outstanding();
    }
    if (amount == 0) {
      revert errors.ZeroAmount();
    }

    if (!IFrabricWhitelistCore(whitelist).hasKYC(msg.sender)) {
      revert NotKYC(msg.sender);
    }

    // Mint before transferring to prevent re-entrancy causing the Crowdfund to exceed its target
    transferAllowed = true;
    // Proper since this only runs up to target which is a uint112
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
    // This refund will go through _distribute. While distribute does ban fee on transfer,
    // _distribute will not.
    // Rebase tokens also exist, and will also screw this over, yet there's only so much we can do
    // This contract can also be blacklisted and have all its funds frozen
    // Such cases are deemed as incredibly out of scope for discussion here (and elsewhere)
    uint256 balance = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    if ((IERC20(token).balanceOf(address(this)) - balance) != amount) {
      revert FeeOnTransfer(token);
    }
    lastDepositTime = uint64(block.timestamp);
    emit Deposit(msg.sender, amount);

    return amount;
  }

  // Enable withdrawing funds before the target is reached
  function withdraw(uint112 amount) external override {
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    if (amount == 0) {
      revert errors.ZeroAmount();
    }

    // If the target has been reached, give the governor 24 hours to execute
    if ((outstanding() == target) && (uint64(block.timestamp - 24 hours) < lastDepositTime)) {
      revert CrowdfundReached();
    }

    _burn(msg.sender, amount);
    emit Withdraw(msg.sender, amount);

    IERC20(token).safeTransfer(msg.sender, amount);
  }

  // Cancel a Crowdfund before execution starts
  function cancel() external override {
    if (msg.sender != governor) {
      revert NotGovernor(msg.sender, governor);
    }
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }

    // Set the State to refunding
    state = State.Refunding;
    uint256 balance = IERC20(token).balanceOf(address(this));
    // This should never happen, yet since anyone can transfer to this contract...
    // it theoretically can. This ensures that the maximum possible amount will
    // be paid out. While some may still be trapped, an amount >= target will be
    // refunded, as intended
    if (balance > type(uint112).max) {
      balance = type(uint112).max;
    }
    _distribute(token, uint112(balance));
    emit StateChange(state);
  }

  // Transfer the funds from a Crowdfund to the governor for execution
  function execute() external override {
    if (msg.sender != governor) {
      revert NotGovernor(msg.sender, governor);
    }
    if (outstanding() != target) {
      revert CrowdfundNotReached();
    }
    if (state != State.Active) {
      revert InvalidState(state, State.Active);
    }
    state = State.Executing;
    emit StateChange(state);

    IERC20(token).safeTransfer(governor, target);
  }

  // Take a executing Crowdfund which externally failed and return the leftover funds
  function refund(uint112 amount) external override {
    if (msg.sender != governor) {
      revert NotGovernor(msg.sender, governor);
    }
    if (state != State.Executing) {
      revert InvalidState(state, State.Executing);
    }
    state = State.Refunding;
    emit StateChange(state);

    // Allows the governor to refund 0
    // If this is improper, they should be bond slashed accordingly
    // They should be bond slashed for any refunded amount which is too low
    // Upon arbitration ruling the amount is too low, the governor could step in
    // and issue a new distribution
    if (amount != 0) {
      distribute(token, amount);
    }
  }

  function finish() external override {
    if (msg.sender != governor) {
      revert NotGovernor(msg.sender, governor);
    }
    if (state != State.Executing) {
      revert InvalidState(state, State.Executing);
    }
    state = State.Finished;
    emit StateChange(state);
  }

  // Allow redeeming Crowdfund tokens to receive Thread tokens
  function redeem(address depositor) external override {
    if (state != State.Finished) {
      revert InvalidState(state, State.Finished);
    }
    uint256 balance = balanceOf(depositor);
    if (balance == 0) {
      revert errors.ZeroAmount();
    }
    _burn(depositor, balance);
    IERC20(IDAOCore(thread).erc20()).safeTransfer(depositor, normalizeRaiseToThread(balance));
  }

  // While it would be nice to have a recovery function here, the integration with DistributionERC20
  // means that can't feasibly be done (without adding more tracking to DistributionERC20 on expected balances)
  // It's not worth the hassle at this time
}
