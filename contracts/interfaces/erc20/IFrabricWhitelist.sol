// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import {errors} from "../common/Errors.sol";
import "../common/IComposable.sol";

interface IFrabricWhitelistCore is IComposable {
  event Whitelisted(address indexed person, bool indexed whitelisted);

  // The ordinal value of the enum increases with accreditation
  enum Status {
    Null,
    Removed,
    Whitelisted,
    KYC
  }

  function parent() external view returns (address);

  function setParent(address parent) external;
  function whitelist(address person) external;
  function setKYC(address person, bytes32 hash, uint256 nonce) external;

  function whitelisted(address person) external view returns (bool);
  function hasKYC(address person) external view returns (bool);
  function removed(address person) external view returns (bool);
  function status(address person) external view returns (Status);
}

interface IFrabricWhitelist is IFrabricWhitelistCore {
  event ParentChange(address oldParent, address newParent);
  // Info shouldn't be indexed when you consider it's unique per-person
  // Indexing it does allow retrieving the address of a person by their KYC however
  // It's also just 750 gas on an infrequent operation
  event KYCUpdate(address indexed person, bytes32 indexed oldInfo, bytes32 indexed newInfo, uint256 nonce);
  event GlobalAcceptance();

  function global() external view returns (bool);

  function kyc(address person) external view returns (bytes32);
  function kycNonces(address person) external view returns (uint256);
  function explicitlyWhitelisted(address person) external view returns (bool);
  function removedAt(address person) external view returns (uint256);
}

error AlreadyWhitelisted(address person);
error Removed(address person);
error NotWhitelisted(address person);
error NotRemoved(address person);
error NotKYC(address person);
