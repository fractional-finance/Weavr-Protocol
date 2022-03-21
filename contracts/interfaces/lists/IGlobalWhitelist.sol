// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "./IInfoWhitelist.sol";

interface IGlobalWhitelist is IInfoWhitelist {
  function explicitlyWhitelisted(address person) external view returns (bool);
}
