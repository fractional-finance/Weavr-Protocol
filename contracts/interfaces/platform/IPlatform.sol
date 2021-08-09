// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import "../modifiers/IOwnable.sol";
import "../lists/IGlobalWhitelist.sol";

interface IPlatform is IOwnable, IGlobalWhitelist {
  event AssetMinted(uint256 indexed id, string data);
  event AddedAssetDeployer(uint256 indexed id, address indexed deployer);
  event DisabledAssetDeployer(uint256 indexed id);
  event AssetDeployed(uint256 indexed deployerID, address indexed oracle,
                      uint256 indexed assetID, address assetContract, uint256 shares);

  function setWhitelisted(address person, bytes32 dataHash) external;

  function createNFT(string calldata data) external returns (uint256);

  function addAssetDeployer(address deployer) external;
  function removeAssetDeployer(uint256 deployer) external;

  function deployAsset(uint256 deployer, address oracle, uint256 nft, uint256 shares) external returns (address);

  function proposePaper(address asset, string calldata info) external returns (uint256);
  function proposePlatformChange(address asset, string calldata info, address platform,
                                 uint256 newNFT) external returns (uint256);
 function proposeOracleChange(address asset, string calldata info, address newOracle) external returns (uint256);
 function proposeDissolution(address asset, string calldata info, address purchaser,
                             address token, uint256 purchaseAmount) external returns (uint256);
}
