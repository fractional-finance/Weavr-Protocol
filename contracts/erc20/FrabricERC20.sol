// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./DistributionERC20.sol";
import "./FrabricWhitelist.sol";
import "./IntegratedLimitOrderDEX.sol";

import "../interfaces/erc20/IAuction.sol";

import "../interfaces/erc20/IFrabricERC20.sol";

// FrabricERC20s are tokens with a built in limit order DEX, along with governance and distribution functionality
// The owner can also mint tokens, with a whitelist enforced unless disabled by owner, defaulting to a parent whitelist
// Finally, the owner can pause transfers, intended for migrations and dissolutions
contract FrabricERC20 is OwnableUpgradeable, PausableUpgradeable, DistributionERC20, FrabricWhitelist, IntegratedLimitOrderDEX, IFrabricERC20Initializable {
  bool public override mintable;
  address public override auction;

  mapping(address => uint64) public override frozenUntil;
  bool internal _removal;

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool _mintable,
    address parentWhitelist,
    address tradedToken,
    address _auction
  ) external override initializer {
    __Ownable_init();
    __Pausable_init();
    __DistributionERC20_init(name, symbol);
    __FrabricWhitelist_init(parentWhitelist);
    __IntegratedLimitOrderDEX_init(tradedToken);

    __Composable_init("FrabricERC20", false);
    supportsInterface[type(OwnableUpgradeable).interfaceId] = true;
    supportsInterface[type(PausableUpgradeable).interfaceId] = true;
    supportsInterface[type(IFrabricERC20).interfaceId] = true;

    // Whitelist the initializer
    // This is the Frabric's deployer/the ThreadDeployer
    // If the former, they should remove their own whitelisting
    // If the latter, this is intended behavior
    _setWhitelisted(msg.sender, keccak256("Initializer"));

    // Make sure the supply is within bounds
    // The DAO code sets an upper bound of signed<int>.max
    // Uniswap and more frequently use uint112 which is a perfectly functional bound
    // The DAO code accordingly uses int128 which maintains storage efficiency
    // while supporting the full uint112 range
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
  constructor() Composable("FrabricERC20") initializer {}

  // Redefine ERC20 functions so the DEX can pick them up as overrides and call them
  function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, IntegratedLimitOrderDEX) {
    ERC20Upgradeable._transfer(from, to, amount);
  }
  function balanceOf(
    address account
  ) public view override(IERC20Upgradeable, ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint256) {
    return ERC20Upgradeable.balanceOf(account);
  }
  function decimals() public view override(ERC20Upgradeable, IntegratedLimitOrderDEX) returns (uint8) {
    return ERC20Upgradeable.decimals();
  }

  // Also define frozen so the DEX can prevent further orders from being placed
  function frozen(address person) public view override returns (bool) {
    return block.timestamp <= frozenUntil[person];
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

  function freeze(address person, uint64 until) external override onlyOwner {
    frozenUntil[person] = until;
    emit Freeze(person, until);
  }

  function _remove(address person) internal override {
    // If they were already removed, return
    if (removed(person)) {
      return;
    }
    _setRemoved(person);

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
      // every function which calls this is nonReentrant and it is set to false after the loop
      _removal = true;
      for (uint256 i = 0; i < rounds; i++) {
        // If this is the final round, compensate for any rounding errors
        if (i == (rounds - 1)) {
          amount = balance - ((balance / rounds) * i);
        }

        _transfer(person, auction, amount);

        // List the transferred tokens
        IAuctionCore(auction).listTransferred(
          address(this),
          tradedToken,
          person,
          uint64(block.timestamp + (i * (1 weeks))),
          1 weeks
        );
      }
      _removal = false;
    }

    emit Removal(person, balance);
  }

  function remove(address person) public override nonReentrant {
    // Check they were actually removed from the whitelist
    if (whitelisted(person)) {
      revert Whitelisted(person);
    }
    _remove(person);
  }

  // Whitelist functions
  function whitelisted(
    address person
  ) public view override(IntegratedLimitOrderDEX, FrabricWhitelist, IWhitelist) returns (bool) {
    return FrabricWhitelist.whitelisted(person) && (!removed(person));
  }

  function removed(address person) public view override(IntegratedLimitOrderDEX, FrabricWhitelist, IFrabricWhitelist) returns (bool) {
    return FrabricWhitelist.removed(person);
  }

  function setParentWhitelist(address whitelist) external override onlyOwner {
    _setParentWhitelist(whitelist);
  }

  // nonReentrant would be overkill given onlyOwner except this needs to not be the initial vector
  // while re-entrancy happens through functions labelled nonReentrant
  // While the only external calls should be completely in-ecosystem and therefore to trusted code,
  // _remove really isn't the thing to play around with
  function setWhitelisted(address person, bytes32 dataHash) external override onlyOwner nonReentrant {
    _setWhitelisted(person, dataHash);

    // If removing, remove them now
    // This will only apply to the Frabric/Thread in question
    // For a Frabric removal, this will remove them from the global whitelist,
    // and enable calling remove on any Thread. For a Thread, this won't change
    // the whitelist at all, as it'll still be whitelisted on the Frabric
    if (dataHash == bytes32(0)) {
      _remove(person);
    }
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

    if ((!_removal) && (!_inDEX)) {
      // Whitelisted from or minting
      // A non-whitelisted actor may have tokens if they were removed from the whitelist
      // and remove has yet to be called. That's why this code is inside `if !_removal`
      // !_inDEX is simply an optimization as the DEX checks traders are whitelisted itself

      // Technically, whitelisted is an interaction, as discussed in IntegratedLimitOrderDEX
      // As stated there, it's trusted to not be idiotic AND it's view, limiting potential
      if ((!whitelisted(from)) && (from != address(0))) {
        revert NotWhitelisted(from);
      }

      // Regarding !_removal, placed here as a gas optimization
      // The Auction contract transferred to during removals is whitelisted so this
      // could be outside this block without issue. If it wasn't whitelisted,
      // anyone could call remove on it, which would be exceptionally problematic
      // (and it couldn't transfer tokens to auction winners)
      if (!whitelisted(to)) {
        revert NotWhitelisted(to);
      }

      // If the person is being removed, or if the DEX is executing a standing order,
      // this is disregarded. It's only if they're trying to transfer after being frozen
      // that this should matter (and the DEX ensures they can't place new orders)
      if (frozen(from)) {
        revert Frozen(from);
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
