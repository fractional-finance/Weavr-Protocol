// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

interface IPausable {
  function pause() external;
  function unpause() external;
  function paused() external view returns (bool);
}
