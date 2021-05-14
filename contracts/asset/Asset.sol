// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../lists/ScoreList.sol";
import "./AssetERC20.sol";

contract Asset is AssetERC20, ScoreList {
  constructor(
    address fractionalNFT,
    uint256 nftID,
    uint256 shares,
    address fractionalWhitelist,
    address dividendToken,
    address superfluid,
    address ida
  ) AssetERC20(fractionalNFT, nftID, shares, fractionalWhitelist, dividendToken, superfluid, ida) ScoreList(200) {}

  function setScore(address person, uint8 scoreValue) public onlyOwner {
    _setScore(person, scoreValue);
  }

  /*
  event OracleInfo
  event VoteProposal
  event Vote
  event VoteCompleted

  // takes in a non-reusable ID to distinguish profit submissions allow risk free submission retries
  function submitProfit()
  */
}
