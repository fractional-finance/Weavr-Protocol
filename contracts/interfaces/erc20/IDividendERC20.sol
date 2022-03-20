// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IDividendERC20 {
  event Distributed(address indexed token, uint256 amount);
  event Claimed(address indexed person, uint256 indexed id, uint256 amount);

  function claimedDistribution(address person, uint256 id) external view returns (bool);

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}
