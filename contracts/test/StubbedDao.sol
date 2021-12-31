// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../dao/Dao.sol";
import "../asset/AssetERC20.sol";
import "./ERC20.sol";

contract StubbedDao is Dao, ERC20 {

    mapping(address => Checkpoint[]) private _checkpoints;
    event ProposedPlatformChange(uint256 indexed id, address indexed platform);
    event ProposedOracleChange(uint256 indexed id, address indexed oracle);
    event ProposedDissolution(uint256 indexed id, address indexed purchaser, address token, uint256 purchaseAmount);
    event PlatformChanged(uint256 indexed id, address indexed platform);
    event OracleChanged(uint256 indexed id, address indexed oldOracle, address indexed newOracle);
    event Dissolved(uint256 indexed id, address indexed purchaser, uint256 purchaseAmount);

    address public _oracle;
    address public _platform;
    uint256 public _votes;

    struct Checkpoint {
        uint256 block;
        uint256 balance;
    }


    struct PlatformInfo {
        address platform;
        uint256 nft;
    }

    struct DissolutionInfo {
        address purchaser;
        address token;
        uint256 purchaseAmount;
        bool reclaimed;
    }

    mapping(uint256 => uint256) public proposalVoteHeight;
    // Various extra info for proposals
    mapping(uint256 => PlatformInfo) private _platformChange;
    mapping(uint256 => address) private _oracleChange;
    mapping(uint256 => DissolutionInfo) private _dissolution;

    constructor() ERC20("Integrated Limit Order DEX ERC20", "ILOD") {
        _mint(msg.sender, 1e18);
        _oracle = 0x0000000000000000000000000000000000000001;
        _votes = 0;
        _platform = 0x0000000000000000000000000000000000000000;
    }

    modifier beforeProposal() {
        require((balanceOf(msg.sender) != 0) ||
        (msg.sender == address(_platform)) || (msg.sender == address(_oracle)),
            "Asset: Proposer is not authorized to create a proposal");
        _;
    }

    function proposePaper(string calldata info) beforeProposal() external returns (uint256) {
        uint256 id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
        proposalVoteHeight[id] = block.number;
        return id;
    }

    function proposePlatformChange(string calldata info, address platform,
        uint256 newNFT) beforeProposal() external returns (uint256 id) {
        id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
        proposalVoteHeight[id] = block.number;
        _platformChange[id] = PlatformInfo(platform, newNFT);
        emit ProposedPlatformChange(id, platform);
    }

    function proposeOracleChange(string calldata info,
        address newOracle) beforeProposal() external returns (uint256 id) {
        id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
        proposalVoteHeight[id] = block.number;
        _oracleChange[id] = newOracle;
        emit ProposedOracleChange(id, newOracle);
    }

    function proposeDissolution(string calldata info, address purchaser, address token,
        uint256 purchaseAmount) beforeProposal() external returns (uint256 id) {
        require(purchaseAmount != 0, "Asset: Dissolution amount is 0");
        id = _createProposal(info, block.timestamp + 30 days, balanceOf(msg.sender));
        proposalVoteHeight[id] = block.number;
        _dissolution[id] = DissolutionInfo(purchaser, token, purchaseAmount, false);
        IERC20(token).transferFrom(msg.sender, address(this), purchaseAmount);
        emit ProposedDissolution(id, purchaser, token, purchaseAmount);
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

    function passProposal(uint256 id) external {
        // If this is a dissolution, require they didn't reclaim the funds
        // There's a temporary time window before this function is called where the proposal has expired, yet isn't queued
        // Reclaiming funds is allowed during this time as that looks identical to a failed proposal
        if (_dissolution[id].purchaseAmount != 0) {
            require(!_dissolution[id].reclaimed, "Asset: Dissolution had its funds reclaimed");
        }

        _queueProposal(id, totalSupply());
    }

    // Renegers refers to anyone who has reneged from their stake and therefore should no longer be considered as voters
    function cancelProposal(uint256 id, address[] calldata renegers) external {
        uint256[] memory oldVotes = new uint[](renegers.length);
        uint256[] memory newVotes = new uint[](renegers.length);
        for (uint256 i = 0; i < renegers.length; i++) {
            oldVotes[i] = balanceOfAtHeight(renegers[i], proposalVoteHeight[id]);
            newVotes[i] = balanceOf(renegers[i]);
        }
        _cancelProposal(id, renegers, oldVotes, newVotes);
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

//    function enactProposal(uint256 id) external override {
//        _completeProposal(id);
//
//        if (_platformChange[id].platform != address(0)) {
//            platform = _platformChange[id].platform;
//            nft = _platformChange[id].nft;
//            IERC721(platform).safeTransferFrom(platform, address(this), nft);
//            emit PlatformChanged(id, platform);
//        } else if (_oracleChange[id] != address(0)) {
//            emit OracleChanged(id, oracle, _oracleChange[id]);
//            oracle = _oracleChange[id];
//        } else if (_dissolution[id].purchaseAmount != 0) {
//            _distribute(IERC20(_dissolution[id].token), _dissolution[id].purchaseAmount);
//            IERC721(platform).safeTransferFrom(address(this), _dissolution[id].purchaser, nft);
//            dissolved = true;
//            _pause();
//            emit Dissolved(id, _dissolution[id].purchaser, _dissolution[id].purchaseAmount);
//        }
//    }

    function reclaimDissolutionFunds(uint256 id) external {
        // Require the proposal have ended
        require(!isProposalActive(id), "Asset: Dissolution proposal is active");
        // If the proposal was queued, require it to have been cancelled
        if (getTimeQueued(id) != 0) {
            require(getCancelled(id), "Asset: Dissolution was queued yet not cancelled");
        }

        // Require this is actually a dissolution
        require(_dissolution[id].purchaseAmount != 0, "Asset: Proposal isn't a dissolution");

        // Require the dissolution wasn't already reclaimed
        require(!_dissolution[id].reclaimed, "Asset: Dissolution was already reclaimed");
        _dissolution[id].reclaimed = true;

        // Transfer the tokens
        IERC20(_dissolution[id].token).transfer(_dissolution[id].purchaser, _dissolution[id].purchaseAmount);
    }
}
