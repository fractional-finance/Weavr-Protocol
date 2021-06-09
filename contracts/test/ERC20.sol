// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Instance is ERC20 {
  uint8 public immutable override decimals;
  constructor(uint8 _decimals, string memory name, string memory symbol) ERC20(name, symbol) {
    decimals = _decimals
    _mint(msg.sender, 100 * (10 ** _decimals));
  }
}
