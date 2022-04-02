// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../erc20/FrabricWhitelist.sol";

contract TestWhitelist is FrabricWhitelist {
  function initialize() public initializer {
    __FrabricWhitelist_init(address(0));
  }

  function whitelist(address person) external {
    _setWhitelisted(person, bytes32(uint256(1)));
  }
}