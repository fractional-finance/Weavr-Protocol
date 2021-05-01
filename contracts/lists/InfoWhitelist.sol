// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/lists/IWhitelist.sol";

contract InfoWhitelist is IWhitelist, Ownable {
  event InfoChange(address indexed person, bytes32 info);

  // Intended to point to a hash of the whitelisted party's personal info
  // A simpler, more cost effective whitelist, would use a bool or small int
  // A set could also be extremely efficient
  // This is simple and works for Fractional's overall requirements
  // To use this as a boolean, simply use a data hash of 0x1
  mapping(address => bytes32) private _whitelist;

  constructor() Ownable() {}

  // Set dataHash of 0x0 to remove from whitelist
  function _setWhitelist(address person, bytes32 dataHash) internal {
    _whitelist[person] = dataHash;
    emit WhitelistChange(person, dataHash != bytes32(0));
    emit InfoChange(person, dataHash);
  }

  function setWhitelist(address person, bytes32 dataHash) external override onlyOwner {
    _setWhitelist(person, dataHash);
  }

  function whitelisted(address person) public view virtual override returns (bool) {
    return _whitelist[person] != bytes32(0);
  }


  // public, not external, in case the stored info hash actually contains info
  // Bit flags in the first byte, with a 31-byte hash, would have numerous use cases
  function getInfoHash(address person) public view returns (bytes32) {
    return _whitelist[person];
  }
}
