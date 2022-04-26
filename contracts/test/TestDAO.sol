// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../dao/DAO.sol";

contract TestDAO is DAO {
  event Completed(uint256 id, uint16 proposalType);

  constructor(address erc20) Composable("TestDAO") initializer {
    __Composable_init("TestDAO", true);
    // Uses a time value not used by anything else
    __DAO_init(erc20, 3 * 24 * 60 * 60);
  }

  function canPropose(address participant) public view override returns (bool) {
    return IFrabricERC20(erc20).whitelisted(participant);
  }

  function propose(uint16 pType, bool supermajority, bytes32 info) external {
    _createProposal(pType, supermajority, info);
  }

  function _completeProposal(uint256 id, uint16 pType) internal override {
    emit Completed(id, pType);
  }
}
