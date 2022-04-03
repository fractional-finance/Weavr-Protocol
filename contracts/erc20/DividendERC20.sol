// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IDividendERC20.sol";

// ERC20 Votes expanded with dividend functionality
abstract contract DividendERC20 is ERC20VotesUpgradeable, Composable, IDividendERC20Sum {
  using SafeERC20 for IERC20;

  struct Distribution {
    IERC20 token;
    uint64 block;
    uint256 amount;
  }
  Distribution[] private _distributions;
  mapping(address => mapping(uint256 => bool)) public override claimedDistribution;

  function __DividendERC20_init(string memory name, string memory symbol) internal {
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ERC20Votes_init();

    supportsInterface[type(IERC20).interfaceId] = true;
    supportsInterface[type(IERC20PermitUpgradeable).interfaceId] = true;
    supportsInterface[type(IVotesUpgradeable).interfaceId] = true;
    supportsInterface[type(IDividendERC20).interfaceId] = true;
  }

  // Disable delegation to enable dividends
  // Removes the need to track both historical balances AND historical voting power
  // Also resolves legal liability which is currently not fully explored and may be a concern
  function delegate(address) public pure override(IVotesUpgradeable, ERC20VotesUpgradeable) {
    revert Delegation();
  }
  function delegateBySig(
    address, uint256, uint256, uint8, bytes32, bytes32
  ) public pure override(IVotesUpgradeable, ERC20VotesUpgradeable) {
    revert Delegation();
  }

  // Dividend implementation
  function _distribute(address from, address token, uint256 amount) internal {
    if (amount == 0) {
      revert ZeroAmount();
    }
    if (from != address(this)) {
      IERC20(token).safeTransferFrom(from, address(this), amount);
    }
    _distributions.push(Distribution(IERC20(token), uint64(block.number), amount));
    emit Distributed(token, amount);
  }

  function distribute(address token, uint256 amount) external override {
    _distribute(msg.sender, token, amount);
  }

  function claim(address person, uint256 id) external override {
    if (claimedDistribution[person][id]) {
      revert AlreadyClaimed(id);
    }
    claimedDistribution[person][id] = true;
    uint256 blockNumber = _distributions[id].block;
    uint256 amount = _distributions[id].amount * getPastVotes(person, blockNumber) / getPastTotalSupply(blockNumber);
    if (amount == 0) {
      revert ZeroAmount();
    }
    _distributions[id].token.safeTransfer(person, amount);
    emit Claimed(person, id, amount);
  }
}
