// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IUpgradeable {
  function upgrade(uint256 version, bytes calldata data) external;
}

error NotBeacon(address caller, address beacon);
error NotUpgraded(uint256 version, uint256 versionRequired);
