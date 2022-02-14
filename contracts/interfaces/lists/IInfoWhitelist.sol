// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IWhitelist.sol";

interface IInfoWhitelist is IWhitelist {
  function getInfoHash(address person) external view returns (bytes32);
}
