// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "../interfaces/erc20/IERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Burnable is IERC20Burnable, ERC20 {
    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external override {
        uint256 decreasedAllowance = allowance(account, msg.sender) - amount;

        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 1e18);
    }
}