// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./DividendERC20.sol";
import "./FrabricWhitelist.sol";
import "./IntegratedLimitOrderDEX.sol";

import "../interfaces/auction/IAuction.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

// FrabricERC20s are tokens with a built in limit order DEX, along with governance and dividend functionality
// The owner can also mint tokens, with a whitelist enforced unless disabled by owner, defaulting to a parent whitelist
// Finally, the owner can pause transfers, intended for migrations and dissolutions
contract FrabricERC20 is OwnableUpgradeable, PausableUpgradeable, DividendERC20, FrabricWhitelist, IntegratedLimitOrderDEX, IFrabricERC20 {
  bool public override mintable;
  address public override auction;
  bool internal _removal;

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool _mintable,
    address parentWhitelist,
    address dexToken,
    address _auction
  ) external initializer {
    __DividendERC20_init(name, symbol);
    __Ownable_init();
    __Pausable_init();
    __FrabricWhitelist_init(parentWhitelist);
    __IntegratedLimitOrderDEX_init(dexToken);

    // Whitelist the initializer
    // This is the Frabric's deployer/the ThreadDeployer
    // If the former, they should remove their own whitelisting
    // If the latter, this is intended behavior
    _setWhitelisted(msg.sender, keccak256("Initializer"));

    // Make sure the supply is within bounds
    // The DAO code sets an upper bound of int256.max
    // Uniswap and more frequently use uint112 which is still a very reasonable bound
    if (supply > uint256(type(uint112).max)) {
      revert SupplyExceedsUInt112(supply);
    }

    // Mint the supply
    _mint(msg.sender, supply);
    mintable = _mintable;

    auction = _auction;
    _removal = false;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // Redefine ERC20 functions so the DEX can pick them up as overrides and call them
  function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, IntegratedLimitOrderDEX) {
    ERC20Upgradeable._transfer(from, to, amount);
  }
  function balanceOf(address account) public view override(ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint256) {
    return ERC20Upgradeable.balanceOf(account);
  }
  function decimals() public view override(ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint8) {
    return ERC20Upgradeable.decimals();
  }

  function mint(address to, uint256 amount) external override onlyOwner {
    if (!mintable) {
      revert NotMintable();
    }
    _mint(to, amount);
    if (totalSupply() > uint256(type(uint112).max)) {
      revert SupplyExceedsUInt112(totalSupply());
    }
  }

  function burn(uint256 amount) external override {
    _burn(msg.sender, amount);
  }

  function remove(address person) public override nonReentrant {
    // If removal is true, this is this contract removing them, so ignore whitelist status
    // Else, check if they actually were removed from the whitelist
    if ((!_removal) && (whitelisted(person))) {
      revert Whitelisted(person);
    }
    // Set _removal to false to ensure it's not a concern
    // If it was accidentally left set, anyone could be removed
    // This could be done by splitting the above if and adding an else yet this
    // write should be cheap enough
    _removal = false;

    // Clear the amount they have locked
    locked[person] = 0;

    uint256 balance = balanceOf(person);
    if (balance != 0) {
      uint256 rounds = 4;
      uint256 amount = balance / rounds;
      // Dust, yet create the auction for technical accuracy
      // The real importance is on making sure this code doesn't error as that'll
      // prevent the removal from actually executing
      if (amount == 0) {
        rounds = 1;
      }

      // Set _removal = true for the entire body as multiple transfers will occur
      // While this would be a risk if re-entrancy was possible, or if it was left set,
      // this function is nonReentrant and it is set to false after the loop
      _removal = true;
      for (uint256 i = 0; i < rounds; i++) {
        // If this is the final round, compensate for any rounding errors
        if (i == (rounds - 1)) {
          amount = balance - ((balance / rounds) * i);
        }

        _transfer(person, auction, amount);

        // List the transferred tokens
        IAuction(auction).listTransferred(address(this), dexToken, person, block.timestamp + (i * (1 weeks)), 1 weeks);
      }
      _removal = false;
    }
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

    // If removing, remove them now
    // This will only apply to the Frabric/Thread in question
    // For a Frabric removal, this will remove them from the global whitelist,
    // and enable calling remove on any Thread. For a Thread, this won't change
    // the whitelist at all, as it'll still be whitelisted on the Frabric
    if (dataHash == bytes32(0)) {
      // Set _removal to true so remove doesn't check the whitelist
      // We could also use an external call and a msg.sender check
      _removal = true;
      remove(person);
    }
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

    if (!_removal) {
      // Whitelisted from or minting
      // A non-whitelisted actor may have tokens if they were removed from the whitelist
      // In that case, remove should be called
      // whitelisted is an interaction, extensively discussed in IntegratedLimitOrderDEX
      // As stated there, it's trusted to not be idiotic AND it's view, limiting potential
      if ((!whitelisted(from)) && (from != address(0))) {
        revert NotWhitelisted(from);
      }

      // Placed here as a gas optimization
      // The Auction contract transferred to during removals is whitelisted so it's
      // not removable, and so it can then make its own transfer as needed to complete the auction
      if (!whitelisted(to)) {
        revert NotWhitelisted(to);
      }
    }

    if (paused()) {
      revert CurrentlyPaused();
    }
  }

  function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._afterTokenTransfer(from, to, amount);
    // Require the balance of the sender be greater than the amount of tokens they have on the DEX
    if (balanceOf(from) < locked[from]) {
      revert BalanceLocked(balanceOf(from), locked[from]);
    }
  }
}
