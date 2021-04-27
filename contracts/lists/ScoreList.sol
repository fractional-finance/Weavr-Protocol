// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/lists/IScoreList.sol";

contract ScoreList is IScoreList, Ownable {
  uint8 private _maxScore;
  // _scores are values between 0 -> maxScore, which defines a multiplier to use when voting
  // if maxScore is 0, it isn't used and any score can be assigned
  mapping(address => uint8) private _scores;

  constructor(uint8 maxScoreValue) Ownable() {
    _maxScore = maxScoreValue;
  }

  function maxScore() public view override returns (uint8) {
    return _maxScore;
  }

  function _setScore(address person, uint8 scoreValue) internal {
    require((scoreValue <= _maxScore) || (_maxScore == 0), "Score was greater than the max score");
    _scores[person] = scoreValue;
    emit ScoreChange(person, scoreValue);
  }

  function setScore(address person, uint8 scoreValue) public override onlyOwner {
    _setScore(person, scoreValue);
  }

  function score(address person) public view override returns (uint8) {
    return _scores[person];
  }
}
