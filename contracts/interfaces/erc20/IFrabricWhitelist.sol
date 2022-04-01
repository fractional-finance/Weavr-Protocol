// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface IFrabricWhitelist {
  event ParentWhitelistChange(address oldParent, address newParent);
  // Info shouldn't be indexed when you consider it's unique per-person
  // Indexing it does allow retrieving the address of a person by their KYC however
  // It's also just 750 gas on an infrequent operation
  event WhitelistUpdate(address indexed person, bytes32 indexed oldInfo, bytes32 indexed newInfo);
  event GlobalAcceptance();

  function global() external view returns (bool);
  function parentWhitelist() external view returns (address);
  function info(address person) external view returns (bytes32);

  function whitelisted(address person) external view returns (bool);
  function explicitlyWhitelisted(address person) external view returns (bool);
}

interface IFrabricWhitelistSum is IComposable, IFrabricWhitelist {}

error NotWhitelisted(address person);
