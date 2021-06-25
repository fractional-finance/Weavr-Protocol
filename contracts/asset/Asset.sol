// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../lists/ScoreList.sol";
import "../dao/Dao.sol";
import "./AssetERC20.sol";

import "../interfaces/asset/IAsset.sol";

contract Asset is IAsset, ScoreList, Dao, AssetERC20 {
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

  mapping(uint256 => PlatformInfo) private _platformChange;
  mapping(uint256 => address) private _oracleChange;
  mapping(uint256 => DissolutionInfo) private _dissolution;

  constructor(
    address platform,
    address _oracle,
    uint256 nft,
    uint256 shares
  ) AssetERC20(platform, nft, shares) ScoreList(200) {
    votes = shares;
    oracle = _oracle;
  }

  function _updateVotes(uint256 oldBalance, uint256 newBalance, uint256 oldScore, uint256 newScore) internal {
    uint256 currentVotes = (oldBalance * oldScore) / 100;
    uint256 newVotes = (newBalance * newScore) / 100;
    votes -= currentVotes;
    votes += newVotes;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    _updateVotes(balanceOf(from), balanceOf(from) - amount, score(from), score(to));
    _updateVotes(balanceOf(to), balanceOf(to) + amount, score(to), score(to));
    AssetERC20._beforeTokenTransfer(from, to, amount);
  }

  function setScore(address person, uint8 scoreValue) public override onlyOwner {
    _updateVotes(balanceOf(person), balanceOf(person), score(person), scoreValue);
    _setScore(person, scoreValue);
  }

  function _tallyVotes(address[] calldata voters) internal view {
    uint256 tallied = 0;
    for (uint256 i = 0; i < voters.length; i++) {
      tallied += balanceOf(voters[i]) * score(voters[i]) / 100;
    }
    require(tallied >= (votes / 2) + 1);
  }

  modifier beforeProposal() {
    require((balanceOf(msg.sender) != 0) ||
            (msg.sender == address(platform)) || (msg.sender == address(oracle)));
    _;
  }

  function proposePaper(string calldata info) beforeProposal() external override returns (uint256) {
    require((balanceOf(msg.sender) != 0) || (msg.sender == oracle) || (msg.sender == platform));
    return _createProposal(info, block.timestamp + 30 days);
  }

  function proposePlatformChange(string calldata info, address platform,
                                 uint256 newNFT) beforeProposal() external override returns (uint256 id) {
    require((balanceOf(msg.sender) != 0) || (msg.sender == oracle) || (msg.sender == platform));
    id = _createProposal(info, block.timestamp + 30 days);
    _platformChange[id] = PlatformInfo(platform, newNFT);
    emit ProposedPlatformChange(id, platform);
  }

  function proposeOracleChange(string calldata info,
                               address newOracle) beforeProposal() external override returns (uint256 id) {
    require((balanceOf(msg.sender) != 0) || (msg.sender == oracle) || (msg.sender == platform));
    id = _createProposal(info, block.timestamp + 30 days);
    _oracleChange[id] = newOracle;
    emit ProposedOracleChange(id, newOracle);
  }

  function proposeDissolution(string calldata info, address purchaser, address token,
                              uint256 purchaseAmount) beforeProposal() external override returns (uint256 id) {
    require((balanceOf(msg.sender) != 0) || (msg.sender == oracle) || (msg.sender == platform));
    id = _createProposal(info, block.timestamp + 30 days);
    _dissolution[id] = DissolutionInfo(purchaser, token, purchaseAmount, false);
    IERC20(token).transferFrom(msg.sender, address(this), purchaseAmount);
    emit ProposedDissolution(id, purchaser, token, purchaseAmount);
  }

  function passProposal(uint256 id, address[] calldata voters) public override {
    _tallyVotes(voters);
    _completeProposal(id, voters);

    if (_platformChange[id].platform != address(0)) {
      platform = _platformChange[id].platform;
      nft = _platformChange[id].nft;
      IERC721(platform).safeTransferFrom(platform, address(this), nft);
      emit PlatformChanged(id, platform);
    } else if (_oracleChange[id] != address(0)) {
      emit OracleChanged(id, oracle, _oracleChange[id]);
      oracle = _oracleChange[id];
    } else if (_dissolution[id].purchaseAmount != 0) {
      _distribute(_dissolution[id].token, _dissolution[id].purchaseAmount);
      IERC721(platform).safeTransferFrom(address(this), _dissolution[id].purchaser, nft);
      dissolved = true;
      _pause();
      emit Dissolved(id, _dissolution[id].purchaser, _dissolution[id].purchaseAmount);
    }
  }

  function reclaimDissolutionFunds(uint256 id) external override {
    // Require the proposal have ended
    require(!isProposalActive(id));
    // Require the proposal wasn't passed
    require(!getCompleted(id));

    // Require the dissolution wasn't already reclaimed
    require(!_dissolution[id].reclaimed);
    _dissolution[id].reclaimed = true;

    // Transfer the tokens
    IERC20(_dissolution[id].token).transfer(_dissolution[id].purchaser, _dissolution[id].purchaseAmount);
  }
}
