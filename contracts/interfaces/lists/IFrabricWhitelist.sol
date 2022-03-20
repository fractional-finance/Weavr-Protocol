// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IGlobalWhitelist.sol";

interface IFrabricWhitelist is IGlobalWhitelist {
  event ParentWhitelistChanged(address oldParent, address newParent);
}
