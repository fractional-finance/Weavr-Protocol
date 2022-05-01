// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../dao/FrabricDAO.sol";

contract TestFrabricDAO is FrabricDAO {
  event RemovalHook(address participant);

  constructor(address erc20) Composable("TestFrabricDAO") initializer {
    __Composable_init("TestFrabricDAO", true);
    __FrabricDAO_init("Test Frabric DAO", erc20, 1 weeks, 5);
  }

  function setParent(address _parent) external {
    IFrabricWhitelistCore(erc20).setParent(_parent);
  }

  function whitelist(address person) external {
    IFrabricWhitelistCore(erc20).whitelist(person);
  }

  function setKYC(address person, bytes32 hash, uint256 nonce) external {
    IFrabricWhitelistCore(erc20).setKYC(person, hash, nonce);
  }

  function canPropose(address) public pure override returns (bool) {
    return true;
  }

  function _participantRemoval(address participant) internal override {
    emit RemovalHook(participant);
  }

  function _completeSpecificProposal(uint256, uint256 pType) internal pure override {
    revert UnhandledEnumCase("TestFrabricDAO: _completeSpecificProposal was called", pType);
  }
}
