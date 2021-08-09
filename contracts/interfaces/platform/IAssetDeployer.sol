// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

interface IAssetDeployer {
  function deploy(address oracle, uint256 nft, uint256 shares) external returns (address);
}
