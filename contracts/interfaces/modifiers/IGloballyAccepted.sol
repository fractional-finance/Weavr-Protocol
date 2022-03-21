// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

interface IGloballyAccepted {
  event GlobalAcceptance();

  function global() external view returns (bool);
}
