// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Instance is ERC20 {
  constructor() ERC20("STABLECOIN", "SC") {
    _mint(msg.sender, 1e18);
  }
}
