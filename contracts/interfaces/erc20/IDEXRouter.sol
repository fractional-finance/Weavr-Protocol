// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface IDEXRouter is IComposable {
  function buy(address token, address tradeToken, uint256 payment, uint256 price, uint256 minimumAmount) external;
}
