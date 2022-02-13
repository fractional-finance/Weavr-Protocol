// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

interface IAssetDeployer is IOwnable {
  event Deployed(address indexed implementation, address indexed proxy);

  function implementation() external returns (address);

  function initialize(address _implementation) external {}
  function deploy(bytes memory data) external returns (address) {}
}
