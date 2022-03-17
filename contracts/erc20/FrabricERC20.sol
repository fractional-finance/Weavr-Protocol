// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import "./IntegratedLimitOrderDEX.sol";
import "../lists/FrabricWhitelist.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

// FrabricERC20s are tokens with a built in limit order DEX, along with governance and dividend functionality
// The owner can also mint tokens, with a whitelist enforced unless disabled by owner, defaulting to a parent whitelist
// Finally, the owner can pause transfers, intended for migrations and dissolutions
contract FrabricERC20 is IFrabricERC20, OwnableUpgradeable, PausableUpgradeable, IntegratedLimitOrderDEX, ERC20VotesUpgradeable, FrabricWhitelist {
  using SafeERC20 for IERC20;

  bool public mintable;

  struct Distribution {
    IERC20 token;
    uint256 amount;
    uint256 block;
  }
  Distribution[] private _distributions;
  mapping(address => mapping(uint256 => bool)) public override claimedDistribution;

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool _mintable,
    address parentWhitelist,
    address dexToken
  ) public initializer {
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ERC20Votes_init();
    __Ownable_init();
    __Pausable_init();
    __FrabricWhitelist_init(parentWhitelist);
    __IntegratedLimitOrderDEX_init(dexToken);
    // Shim to allow the default constructor to successfully execute
    // Actual deployments should have the msg.sender in the parent whitelist
    if (supply != 0) {
      _mint(msg.sender, supply);
    }
    mintable = _mintable;
  }

  constructor() {
    initialize("", "", 0, false, address(0), address(0));
  }

  function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, IntegratedLimitOrderDEX) {
    ERC20Upgradeable._transfer(from, to, amount);
  }
  function balanceOf(address account) public view override(ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint256) {
    return ERC20Upgradeable.balanceOf(account);
  }

  function mint(address to, uint256 amount) external override onlyOwner {
    require(mintable);
    _mint(to, amount);
  }

  // Disable delegation to enable dividends
  // Removes the need to track both historical balances AND historical voting power
  function delegate(address) public pure override {
    require(false, "FrabricERC20: Delegation is not allowed");
  }
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) public pure override {
    require(false, "FrabricERC20: Delegation is not allowed");
  }

  // Whitelist functions
  function whitelisted(address person) public view override(IntegratedLimitOrderDEX, IWhitelist, FrabricWhitelist) returns (bool) {
    return FrabricWhitelist.whitelisted(person);
  }
  function setParentWhitelist(address whitelist) external override onlyOwner {
    _setParentWhitelist(whitelist);
  }
  function setWhitelisted(address person, bytes32 dataHash) external override onlyOwner {
    _setWhitelisted(person, dataHash);
  }
  function globallyAccept() external override onlyOwner {
    _globallyAccept();
  }

  // Pause functions
  function paused() public view override(PausableUpgradeable, IFrabricERC20) returns (bool) {
    return PausableUpgradeable.paused();
  }
  function pause() external override onlyOwner {
    _pause();
  }
  function unpause() external override onlyOwner {
    _unpause();
  }

  // Transfer requirements
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
    require(whitelisted(from) || (from == address(0)), "FrabricERC20: Token sender isn't whitelisted");
    require(whitelisted(to) || (to == address(0)), "FrabricERC20: Token recipient isn't whitelisted");
    require(!paused(), "FrabricERC20: Transfers are paused");
  }

  function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._afterTokenTransfer(from, to, amount);
    // Require the balance of the sender be greater than the amount of tokens they have on the DEX
    require(balanceOf(from) >= locked[from], "FrabricERC20: DEX orders exceed balance");
  }

  // Dividend implementation
  function distribute(address token, uint256 amount) external override {
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    _distributions.push(Distribution(IERC20(token), amount, block.number));
    emit Distributed(token, amount);
  }

  function claim(address person, uint256 id) external override {
    require(!claimedDistribution[person][id], "FrabricERC20: Distribution was already claimed");
    claimedDistribution[person][id] = true;
    uint256 blockNumber = _distributions[id].block;
    uint256 amount = _distributions[id].amount * getPastVotes(person, blockNumber) / getPastTotalSupply(blockNumber);
    require(amount != 0, "FrabricERC20: Distribution amount is 0");
    _distributions[id].token.safeTransfer(person, amount);
    emit Claimed(person, id, amount);
  }
}
