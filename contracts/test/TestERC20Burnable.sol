// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/erc20/IERC20Burnable.sol";
import "../erc20/ERC20Burnable.sol";

contract TestERC20Burnable is ERC20Burnable {
    constructor(string memory name, string memory symbol) ERC20Burnable(name, symbol) {}
}
