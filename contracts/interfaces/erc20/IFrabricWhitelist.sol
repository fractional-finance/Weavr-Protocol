// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/Errors.sol";
import "../common/IComposable.sol";

interface IWhitelist {
  function whitelisted(address person) external view returns (bool);
}

interface IFrabricWhitelist is IComposable, IWhitelist {
  event ParentWhitelistChange(address oldParent, address newParent);
  // Info shouldn't be indexed when you consider it's unique per-person
  // Indexing it does allow retrieving the address of a person by their KYC however
  // It's also just 750 gas on an infrequent operation
  event WhitelistUpdate(address indexed person, bytes32 indexed oldInfo, bytes32 indexed newInfo);
  event GlobalAcceptance();

  function global() external view returns (bool);
  function parent() external view returns (address);
  function info(address person) external view returns (bytes32);

  function explicitlyWhitelisted(address person) external view returns (bool);

  function removed(address person) external view returns (bool);
}

error WhitelistingWithZero(address person);
error Removed(address person);
error NotWhitelisted(address person);
error Whitelisted(address person);
