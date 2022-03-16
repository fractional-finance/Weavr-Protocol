// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IBeacon {
  function upgrade(address instance, address code) external;
}
