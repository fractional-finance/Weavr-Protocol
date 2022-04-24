// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../erc20/FrabricWhitelist.sol";

contract TestFrabricWhitelist is FrabricWhitelist {
  function setGlobal() external {
    _setGlobal();
  }

  function setParent(address _parent) external {
    _setParent(_parent);
  }

  function setWhitelisted(address person, bytes32 dataHash) external {
    _setWhitelisted(person, dataHash);
  }

  function remove(address person) external {
    _setRemoved(person);
  }

  constructor(address parent) Composable("TestFrabricWhitelist") initializer {
    __Composable_init("TestFrabricWhitelist", false);
    __FrabricWhitelist_init(parent);
  }
}
