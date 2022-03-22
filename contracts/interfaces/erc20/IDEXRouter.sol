// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

interface IDEXRouter {
  function buy(address token, uint256 payment, uint256 price, uint256 minimumAmount) external;
}
