// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../dao/Dao.sol";
import "./AssetERC20.sol";

import "../interfaces/asset/IAsset.sol";

contract Asset is IAsset, Dao, AssetERC20 {
  address public override oracle;
  uint256 public override votes;

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

  // Height at which a proposal was proposed, and the height of which balances are used
  mapping(uint256 => uint256) public override proposalVoteHeight;
  // Various extra info for proposals
  mapping(uint256 => PlatformInfo) private _platformChange;
  mapping(uint256 => address) private _oracleChange;
  mapping(uint256 => DissolutionInfo) private _dissolution;

  constructor(
    address platform,
    address _oracle,
    uint256 nft,
    uint256 shares,
    string memory symbol
  ) AssetERC20(platform, nft, shares, symbol) {
    votes = shares;
    oracle = _oracle;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    AssetERC20._beforeTokenTransfer(from, to, amount);
  }

  modifier beforeProposal() {
    require((balanceOf(msg.sender) != 0) ||
            (msg.sender == address(platform)) || (msg.sender == address(oracle)));
    _;
  }

  function proposePaper(string calldata info) beforeProposal() external override returns (uint256) {
    uint256 id = _createProposal(info, block.timestamp + 30 days, balanceOfAtHeight(msg.sender, block.number));
    proposalVoteHeight[id] = block.number;
    return id;
  }

  function proposePlatformChange(string calldata info, address platform,
                                 uint256 newNFT) beforeProposal() external override returns (uint256 id) {
    id = _createProposal(info, block.timestamp + 30 days, balanceOfAtHeight(msg.sender, block.number));
    proposalVoteHeight[id] = block.number;
    _platformChange[id] = PlatformInfo(platform, newNFT);
    emit ProposedPlatformChange(id, platform);
  }

  function proposeOracleChange(string calldata info,
                               address newOracle) beforeProposal() external override returns (uint256 id) {
    id = _createProposal(info, block.timestamp + 30 days, balanceOfAtHeight(msg.sender, block.number));
    proposalVoteHeight[id] = block.number;
    _oracleChange[id] = newOracle;
    emit ProposedOracleChange(id, newOracle);
  }

  function proposeDissolution(string calldata info, address purchaser, address token,
                              uint256 purchaseAmount) beforeProposal() external override returns (uint256 id) {
    require(purchaseAmount != 0);
    id = _createProposal(info, block.timestamp + 30 days, balanceOfAtHeight(msg.sender, block.number));
    proposalVoteHeight[id] = block.number;
    _dissolution[id] = DissolutionInfo(purchaser, token, purchaseAmount, false);
    IERC20(token).transferFrom(msg.sender, address(this), purchaseAmount);
    emit ProposedDissolution(id, purchaser, token, purchaseAmount);
  }

  function voteYes(uint256 id) external override {
    _voteYes(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
  }
  function voteNo(uint256 id) external override {
    _voteNo(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
  }
  function abstain(uint256 id) external override {
    _abstain(id, balanceOfAtHeight(msg.sender, proposalVoteHeight[id]));
  }

  function passProposal(uint256 id) external override {
    // If this is a dissolution, require they didn't reclaim the funds
    // There's a temporary time window before this function is called where the proposal has expired, yet isn't queued
    // Reclaiming funds is allowed during this time as that looks identical to a failed proposal
    if (_dissolution[id].purchaseAmount != 0) {
      require(!_dissolution[id].reclaimed, "Asset: Dissolution had its funds reclaimed");
    }

    _queueProposal(id, totalSupply());
  }

  // Renegers refers to anyone who has reneged from their stake and therefore should no longer be considered as voters
  function cancelProposal(uint256 id, address[] calldata renegers) external override {
    uint256[] memory oldVotes = new uint[](renegers.length);
    uint256[] memory newVotes = new uint[](renegers.length);
    for (uint256 i = 0; i < renegers.length; i++) {
      oldVotes[i] = balanceOfAtHeight(renegers[i], proposalVoteHeight[id]);
      newVotes[i] = balanceOf(renegers[i]);
    }
    _cancelProposal(id, renegers, oldVotes, newVotes);
  }

  function enactProposal(uint256 id) external override {
    _completeProposal(id);

    if (_platformChange[id].platform != address(0)) {
      platform = _platformChange[id].platform;
      nft = _platformChange[id].nft;
      IERC721(platform).safeTransferFrom(platform, address(this), nft);
      emit PlatformChanged(id, platform);
    } else if (_oracleChange[id] != address(0)) {
      emit OracleChanged(id, oracle, _oracleChange[id]);
      oracle = _oracleChange[id];
    } else if (_dissolution[id].purchaseAmount != 0) {
      _distribute(IERC20(_dissolution[id].token), _dissolution[id].purchaseAmount);
      IERC721(platform).safeTransferFrom(address(this), _dissolution[id].purchaser, nft);
      dissolved = true;
      _pause();
      emit Dissolved(id, _dissolution[id].purchaser, _dissolution[id].purchaseAmount);
    }
  }

  function reclaimDissolutionFunds(uint256 id) external override {
    // Require the proposal have ended
    require(!isProposalActive(id), "Asset: Dissolution proposal is active");
    // If the proposal was queued, require it to have been cancelled
    if (getTimeQueued(id) != 0) {
      require(getCancelled(id), "Asset: Dissolution was queued yet not cancelled");
    }

    // Require this is actually a dissolution
    require(_dissolution[id].purchaseAmount != 0);

    // Require the dissolution wasn't already reclaimed
    require(!_dissolution[id].reclaimed);
    _dissolution[id].reclaimed = true;

    // Transfer the tokens
    IERC20(_dissolution[id].token).transfer(_dissolution[id].purchaser, _dissolution[id].purchaseAmount);
  }
}
