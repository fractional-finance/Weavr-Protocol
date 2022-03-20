// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../erc20/IDividendERC20.sol";

interface IBond is IDividendERC20 {
  event Bond(address governor, uint256 amount);
  event Unbond(address governor, uint256 amount);
  event Slash(address governor, uint256 amount);

  function usd() external view returns (address);
  function token() external view returns (address);

  function bond(uint256 amount) external;
  function unbond(address bonder, uint256 amount) external;
  function slash(address bonder, uint256 amount) external;
}
