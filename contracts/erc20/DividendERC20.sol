// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/erc20/IDividendERC20.sol";

// ERC20 Votes expanded with dividend functionality
abstract contract DividendERC20 is ERC20VotesUpgradeable, IDividendERC20 {
  using SafeERC20 for IERC20;

  struct Distribution {
    IERC20 token;
    uint256 amount;
    uint256 block;
  }
  Distribution[] private _distributions;
  mapping(address => mapping(uint256 => bool)) public override claimedDistribution;

  function __DividendERC20_init(string memory name, string memory symbol) internal {
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ERC20Votes_init();
  }

  // Disable delegation to enable dividends
  // Removes the need to track both historical balances AND historical voting power
  // Also resolves legal liability which is currently not fully explored and may be a concern
  function delegate(address) public pure override {
    require(false, "DividendERC20: Delegation is not allowed");
  }
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) public pure override {
    require(false, "DividendERC20: Delegation is not allowed");
  }

  // Dividend implementation
  function distribute(address token, uint256 amount) external override {
    require(amount != 0, "Dividend: Amount can't be zero");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    _distributions.push(Distribution(IERC20(token), amount, block.number));
    emit Distributed(token, amount);
  }

  function claim(address person, uint256 id) external override {
    require(!claimedDistribution[person][id], "Dividend: Distribution was already claimed");
    claimedDistribution[person][id] = true;
    uint256 blockNumber = _distributions[id].block;
    uint256 amount = _distributions[id].amount * getPastVotes(person, blockNumber) / getPastTotalSupply(blockNumber);
    require(amount != 0, "Dividend: Distribution amount is 0");
    _distributions[id].token.safeTransfer(person, amount);
    emit Claimed(person, id, amount);
  }
}
