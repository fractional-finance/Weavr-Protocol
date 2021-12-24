// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../dao/Dao.sol";
import "../asset/AssetERC20.sol";

contract StubbedDao is ERC20, Dao {

    mapping(uint256 => uint256) public proposalVoteHeight;
    address oracle;
    address platform;
    constructor() ERC20("Integrated DAO", "IDAO") {
        platform = 0x0000000000000000000000000000000000000000;
        oracle = 0x0000000000000000000000000000000000000000;
    }

//    modifier beforeProposal() {
//    require((balanceOf(msg.sender) != 0) ||
//            (msg.sender == address(platform)) || (msg.sender == address(oracle)),
//            "Asset: Proposer is not authorized to create a proposal");
//    _;
//  }

    function proposePaper(string calldata info) external returns (uint256) {
    uint256 id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
    proposalVoteHeight[id] = block.number;
    return id;
  }
}

