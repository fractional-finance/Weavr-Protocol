// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../interfaces/common/IComposable.sol";

abstract contract Composable is IComposableSum {
  bytes32 public override contractName;
  // Version is global, and not per-interface, as interfaces aren't "DAO" and "FrabricDAO"
  // Any version which changes the API would change the interface ID and therefore break continuinity
  uint256 public override version;
  mapping(bytes4 => bool) public override supportsInterface;

  // Doesn't have initializer as it's intended to be used by both upgradeable and non-upgradeable contracts
  // Avoids needing non-upgradeable contracts to descend from Initializable when this is harmless to run multiple times
  // (and internal)
  function __Composable_init() internal {
    supportsInterface[type(IERC165Upgradeable).interfaceId] = true;
    supportsInterface[type(IComposable).interfaceId] = true;
  }
}
