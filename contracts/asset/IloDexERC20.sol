// Enables testing of the IntegratedLimitOrderDex contract.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IntegratedLimitOrderDex.sol";

contract IloDexERC20 is ERC20, IntegratedLimitOrderDex {
  constructor() ERC20("Integrated Limit Order DEX ERC20", "ILOD") {
    _mint(msg.sender, 1e18);
  }
}
