// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../common/Composable.sol";

contract TestComposable is Composable {
  constructor(bool code, bool finalized) Composable("TestComposable") initializer {
    if (code) {
      return;
    }
    __Composable_init("TestComposable", finalized);
  }
}
