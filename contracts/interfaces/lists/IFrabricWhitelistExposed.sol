// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IGlobalWhitelist.sol";

interface IFrabricWhitelistExposed is IGlobalWhitelist {
  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;
}
