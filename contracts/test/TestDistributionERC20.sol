// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "../erc20/DistributionERC20.sol";

contract TestDistributionERC20 is DistributionERC20 {
  constructor(string memory name, string memory symbol) Composable("TestDistributionERC20") initializer {
    __Composable_init("TestDistributionERC20", true);
    __DistributionERC20_init(name, symbol);

    // Mint 1m with 18 decimals to the sender
    _mint(msg.sender, 1000000 * 1e18);
  }
}
