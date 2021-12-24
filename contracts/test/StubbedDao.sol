// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../dao/Dao.sol";
import "../asset/AssetERC20.sol";

contract StubbedDao is ERC20, Dao {

    mapping(address => Checkpoint[]) private _checkpoints;
    mapping(uint256 => uint256) public proposalVoteHeight;
    address oracle;
    address platform;
    constructor() ERC20("Integrated DAO", "IDAO") {
        platform = 0x0000000000000000000000000000000000000000;
        oracle = 0x0000000000000000000000000000000000000000;
    }

    struct Checkpoint {
        uint256 block;
        uint256 balance;
    }

    function balanceOfAtHeight(address person, uint256 height) public view returns (uint256) {
        // Only run when the balances have finalized; prevents flash loans from being used
        require(height < block.number, "AssetERC20: Height is either this block or in the future");

        // No balance or earliest balance was after specified height
        if ((_checkpoints[person].length == 0) || (_checkpoints[person][0].block > height)) {
            return 0;
        }

        // Most recent checkpoint is accurate
        if (_checkpoints[person][_checkpoints[person].length - 1].block <= height) {
            return _checkpoints[person][_checkpoints[person].length - 1].balance;
        }

        // Binary search for the applicable checkpoint
        // Choose the bottom of the median
        uint i = (_checkpoints[person].length / 2) - 1;
        // Look for the most recent checkpoint before this block
        // i + 1 is guaranteed to exist as it is never the most recent checkpoint
        // In the case of a single checkpoint, it IS the most recent checkpoint, and therefore would've been caught above
        while (!((_checkpoints[person][i].block <= height) && (_checkpoints[person][i + 1].block > height))) {
            if (_checkpoints[person][i].block < height) {
                // Move up
                // Will never move up to the most recent checkpoint as 1 (the final step) / 2 is 0
                i += (_checkpoints[person].length - i) / 2;
            } else {
                // Move down
                i = i / 2;
            }
        }
        return _checkpoints[person][i].balance;
    }

    modifier beforeProposal() {
    require((balanceOf(msg.sender) != 0) ||
            (msg.sender == address(platform)) || (msg.sender == address(oracle)),
            "Asset: Proposer is not authorized to create a proposal");
    _;
  }

    function proposePaper(string calldata info) external returns (uint256) {
    uint256 id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
    proposalVoteHeight[id] = block.number;
    return id;
  }

    function voteYes(uint256 id) external {
        _voteYes(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
    }
    function voteNo(uint256 id) external {
        _voteNo(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
    }
    function abstain(uint256 id) external {
        _abstain(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
    }
}

