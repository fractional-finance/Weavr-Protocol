// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IGloballyAccepted {
  function globallyAccept() external;
  function global() external view returns (bool);
}
