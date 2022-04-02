// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../interfaces/common/IComposable.sol";

abstract contract Composable is IComposableSum {
  // Doesn't use "name" due to IERC20 using "name"
  bytes32 public override contractName;
  // Version is global, and not per-interface, as interfaces aren't "DAO" and "FrabricDAO"
  // Any version which changes the API would change the interface ID and therefore break continuinity
  uint256 public override version;
  mapping(bytes4 => bool) public override supportsInterface;

  // Code should set its name so Beacons can identify code
  // That said, code shouldn't declare support for interfaces or have any version
  // Hence this
  // Due to solidity requirements, final constracts (non-proxied) which call init
  // yet still use constructors will have to call this AND init. It's a minor
  // gas inefficiency not worth optimizing around
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(string memory name) {
    contractName = keccak256(bytes(name));
  }

  // Doesn't have onlyInitializing as it's intended to be used by both upgradeable and non-upgradeable contracts
  // Avoids needing non-upgradeable contracts to descend from Initializable when this should never be in an exposed path
  // It should always be in an initializer or constructor which can only be called once anyways
  function __Composable_init(string memory name, bool finalized) internal {
    contractName = keccak256(bytes(name));
    if (!finalized) {
      version = 1;
    } else {
      version = type(uint256).max;
    }

    supportsInterface[type(IERC165Upgradeable).interfaceId] = true;
    supportsInterface[type(IComposable).interfaceId] = true;
  }
}