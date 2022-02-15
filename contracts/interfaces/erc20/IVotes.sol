// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IVotes {
  function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
}
