// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import "../asset/Asset.sol";
import "../interfaces/platform/IAssetDeployer.sol";

contract AssetDeployer is IAssetDeployer {
  function deploy(address oracle, uint256 nft, uint256 shares, string memory symbol) external override returns (address) {
    return address(new Asset(msg.sender, oracle, nft, shares, symbol));
  }
}