// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Instance is ERC20 {
  uint8 public immutable _decimals;
  constructor(uint8 __decimals, string memory name, string memory symbol) ERC20(name, symbol) {
    _decimals = __decimals;
    _mint(msg.sender, 100 * (10 ** __decimals));
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
