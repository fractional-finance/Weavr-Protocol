// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IScoreList {
  function maxScore() external view returns (uint8);
  function setScore(address person, uint8 scoreValue) external;
  function score(address person) external view returns (uint8);

  event ScoreChange(address indexed person, uint8 indexed score);
}
