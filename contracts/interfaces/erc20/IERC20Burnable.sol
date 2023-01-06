// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Burnable is IERC20{
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}
