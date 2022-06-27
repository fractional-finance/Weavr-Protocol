// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IDistributionERC20.sol";

/**
 * @title DistributionERC20
 * @author Fractional Finance
 * @notice This contract expands ERC20Votes with distribution functionality
 */
abstract contract DistributionERC20 is ReentrancyGuardUpgradeable, ERC20VotesUpgradeable, Composable, IDistributionERC20 {
  using SafeERC20 for IERC20;

  struct DistributionStruct {
    address token;
    uint32 block;
    // 8 bytes left ^
    // 4 bytes left v
    uint112 amount; // If Uniswap can do it... also fine for our use case
    uint112 supply; // Bounds descendants into not minting past uint112
  }
  // This could be an array yet gas testing on an isolate contract showed writing
  // new structs was roughly 200 gas more expensive while reading to memory was
  // roughly 2000 gas cheaper
  // This was including the monotonic uint256 increment
  // It's also better to use a mapping as we can extend the struct later if needed
  uint256 private _nextID;
  mapping(uint256 => DistributionStruct) private _distributions;
  /// @notice Mapping of distribution -> user -> whether or not it's been claimed
  mapping(uint256 => mapping(address => bool)) public override claimed;

  uint256[100] private __gap;

  function __DistributionERC20_init(string memory name, string memory symbol) internal {
    __ReentrancyGuard_init();
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ERC20Votes_init();

    supportsInterface[type(IERC20).interfaceId] = true;
    supportsInterface[type(IERC20PermitUpgradeable).interfaceId] = true;
    supportsInterface[type(IVotesUpgradeable).interfaceId] = true;
    supportsInterface[type(IDistributionERC20).interfaceId] = true;
  }

  // Doesn't hook into _transfer as _mint doesn't pass through it
  function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._afterTokenTransfer(from, to, amount);
    // Delegate to self to track voting power, if it isn't already tracked
    if (delegates(to) == address(0x0)) {
      super._delegate(to, to);
    }
  }

  // Disable delegation to enable distributions
  // Removes the need to track both historical balances AND historical voting power
  // Also resolves legal liability which is currently not fully explored and may be a concern
  // While we may want voting delegation in the future, we'd have to duplicate the checkpointing
  // code now to keep ERC20Votes' private variables for votes as, truly, votes. It's better
  // to just duplicate it in the future if we need to, which also gives us more control
  // over the process
  function _delegate(address, address) internal pure override {
    revert Delegation();
  }

  // Distribution implementation
  function _distribute(address token, uint112 amount) internal returns (uint256 id) {
    if (amount == 0) {
      revert ZeroAmount();
    }

    id = _nextID;
    _nextID++;
    _distributions[id] = DistributionStruct(
      token,
      uint32(block.number - 1),
      amount,
      // Cache the supply so each claim doesn't have to repeat this binary search
      uint112(getPastTotalSupply(block.number - 1))
    );
    emit Distribution(id, token, amount);
  }

  /**
   * @notice Distribute a token to the holder of this token
   * @param token Token to be distributed
   * @param amount Amount of tokens to be distributed
   * @return id ID of the distribution
   */
  function distribute(address token, uint112 amount) public override nonReentrant returns (uint256) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    // This does mean USDT distributions could theoretically break at some point
    // in the future and any automatic flow expecting this to work could break with it
    // Fee-on-transfer is just incredibly complicated to deal with (as you need to use
    // a re-entrancy vulnerable balance check) and not easily integrated here. Because
    // this contract is used as a parent of Crowdfund, if you could re-enter on
    // this transferFrom call, you could buy Crowdfund tokens with funds then attributed
    // to this distribution. This either means placing nonReentrant everywhere or just
    // banning idiotic token designs in places like this
    if (IERC20(token).balanceOf(address(this)) != (balance + amount)) {
      revert FeeOnTransfer(token);
    }
    return _distribute(token, amount);
  }

  /// @notice Claim tokens from a distribution
  /// @param id ID of the distribution to claim
  /// @param person User to claim tokens for
  function claim(uint256 id, address person) external override {
    if (claimed[id][person]) {
      revert AlreadyClaimed(id, person);
    }
    claimed[id][person] = true;

    DistributionStruct storage distribution = _distributions[id];
    // Since amount will never exceed distribution.amount, which is a uint112, this is proper
    uint112 amount = uint112(
      uint256(distribution.amount) * getPastVotes(person, distribution.block) / distribution.supply
    );
    // Also verifies this is an actual distribution and not an unset ID
    if (amount == 0) {
      revert ZeroAmount();
    }

    IERC20(distribution.token).safeTransfer(person, uint112(amount));
    emit Claim(id, person, amount);
  }
}
