// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    // Mint 1m with 18 decimals to the sender
    _mint(msg.sender, 1000000 * 1e18);
  }
}
