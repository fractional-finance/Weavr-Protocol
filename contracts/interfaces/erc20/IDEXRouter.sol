// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IDEXRouter {
  function buy(address token, uint256 price, uint256 amount) external;
  function refreshAllowance(address token) external;
}
