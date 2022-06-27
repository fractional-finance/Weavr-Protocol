// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "../erc20/FrabricWhitelist.sol";

contract TestFrabricWhitelist is FrabricWhitelist {
  function setGlobal() external {
    _setGlobal();
  }

  function setParent(address _parent) external override {
    _setParent(_parent);
  }

  function whitelist(address person) external override {
    _whitelist(person);
  }

  function setKYC(address person, bytes32 hash, uint256 nonce) external override {
    _setKYC(person, hash, nonce);
  }

  function remove(address person) external {
    _setRemoved(person);
  }

  constructor(address parent) Composable("TestFrabricWhitelist") initializer {
    __Composable_init("TestFrabricWhitelist", false);
    __FrabricWhitelist_init(parent);
  }
}
