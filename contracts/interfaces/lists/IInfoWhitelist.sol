// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "./IWhitelist.sol";

interface IInfoWhitelist is IWhitelist {
  // Info shouldn't be indexed when you consider it's unique per-person
  // Indexing it does allow retrieving the address of a person by their KYC however
  // It's also just 750 gas on an incredibly infrequent operation
  event InfoChange(address indexed person, bytes32 indexed oldInfo, bytes32 indexed newInfo);

  function getInfoHash(address person) external view returns (bytes32);
}
