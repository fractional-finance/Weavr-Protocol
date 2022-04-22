// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../dao/FrabricDAO.sol";

contract TestFrabricDAO is FrabricDAO {
  constructor(address erc20) Composable("TestFrabricDAO") initializer {
    __Composable_init("TestFrabricDAO", true);
    __FrabricDAO_init("Test Frabric DAO", erc20, 1 weeks, 5);
  }

  function whitelist(address person) external {
    IFrabricERC20(erc20).setWhitelisted(person, bytes32("1"));
  }

  function canPropose(address) public pure override returns (bool) {
    return true;
  }

  function _completeSpecificProposal(uint256, uint256 pType) internal pure override {
    revert UnhandledEnumCase("TestFrabricDAO: _completeSpecificProposal was called", pType);
  }
}
