// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../common/Composable.sol";

contract TestOwnable is Ownable, Composable {
  constructor() Ownable() Composable("TestOwnable") initializer {
    __Composable_init("TestOwnable", false);
    supportsInterface[type(Ownable).interfaceId] = true;
  }
}
