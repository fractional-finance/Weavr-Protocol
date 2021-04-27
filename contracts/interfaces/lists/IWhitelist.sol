// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWhitelist {
  function setWhitelist(address person, bytes32 dataHash) external;
  function whitelisted(address person) external view returns (bool);

  event WhitelistChange(address indexed person, bool whitelisted);
}
