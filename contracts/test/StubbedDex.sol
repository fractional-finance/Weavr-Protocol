// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../asset/IntegratedLimitOrderDex.sol";

// Enables testing of the IntegratedLimitOrderDex contract.
contract StubbedDex is ERC20, IntegratedLimitOrderDex {
  constructor() ERC20("Integrated Limit Order DEX ERC20", "ILOD") {
    _mint(msg.sender, 1e18);
  }
}
