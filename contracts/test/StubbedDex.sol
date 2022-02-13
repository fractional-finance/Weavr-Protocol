// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../asset/IntegratedLimitOrderDex.sol";

// Enables testing of the IntegratedLimitOrderDex contract.
contract StubbedDex is ERC20, IntegratedLimitOrderDex {
  constructor() {
    ERC20.initialize("Integrated Limit Order DEX ERC20", "ILOD");
    _mint(msg.sender, 1e18);
  }
}
