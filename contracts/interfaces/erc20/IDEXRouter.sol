// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface IDEXRouter {
  function buy(address token, uint256 payment, uint256 price, uint256 minimumAmount) external;
}

interface IDEXRouterSum is IComposableSum, IDEXRouter {}
