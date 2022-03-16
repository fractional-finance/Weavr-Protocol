// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IBeaconProxied {
  function beacon() external view returns (address);
}
