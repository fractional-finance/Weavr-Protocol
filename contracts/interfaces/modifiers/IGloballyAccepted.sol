// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IGloballyAccepted {
  event GlobalAcceptance();

  function global() external view returns (bool);
}
