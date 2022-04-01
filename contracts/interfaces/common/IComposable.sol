// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

interface IComposable {
  function contractName() external returns (bytes32);
  // Returns uint256 max if not upgradeable
  function version() external returns (uint256);
}

interface IComposableSum is IERC165Upgradeable, IComposable {}
