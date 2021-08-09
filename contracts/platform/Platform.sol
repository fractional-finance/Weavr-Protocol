// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "../modifiers/Ownable.sol";
import "../lists/GlobalWhitelist.sol";

import "../interfaces/asset/IAsset.sol";
import "../interfaces/platform/IAssetDeployer.sol";
import "../interfaces/platform/IPlatform.sol";

contract Platform is ERC721, Ownable, GlobalWhitelist, IPlatform {
  uint256 internal _asset = 0;
  uint256 internal _assetDeployer = 0;
  mapping(uint256 => IAssetDeployer) internal _assetDeployers;

  constructor() ERC721("Fractional Platform", "FRACTIONAL") Ownable() GlobalWhitelist() {}

  function setWhitelisted(address person, bytes32 dataHash) onlyOwner external override {
    _setWhitelisted(person, dataHash);
  }

  function createNFT(string calldata data) onlyOwner external override returns (uint256) {
    _safeMint(msg.sender, _asset);
    _asset++;
    emit AssetMinted(_asset, data);
    return _asset - 1;
  }

  function addAssetDeployer(address deployer) onlyOwner external override {
    _assetDeployers[_assetDeployer] = IAssetDeployer(deployer);
    emit AddedAssetDeployer(_assetDeployer, deployer);
    _assetDeployer++;
  }

  function removeAssetDeployer(uint256 deployer) onlyOwner external override {
    _assetDeployers[deployer] = IAssetDeployer(address(0));
    emit DisabledAssetDeployer(deployer);
  }

  function deployAsset(uint256 deployer, address oracle, uint256 nft,
                       uint256 shares, string memory symbol) onlyOwner external override returns (address asset) {
    require(address(_assetDeployers[deployer]) != address(0));
    asset = _assetDeployers[deployer].deploy(oracle, nft, shares, symbol);
    emit AssetDeployed(deployer, oracle, nft, asset, shares, symbol);
  }

  function proposePaper(address asset, string calldata info) onlyOwner external override returns (uint256) {
    return IAsset(asset).proposePaper(info);
  }

  function proposePlatformChange(address asset, string calldata info, address platform,
                                 uint256 newNFT) onlyOwner external override returns (uint256) {
    return IAsset(asset).proposePlatformChange(info, platform, newNFT);
  }

  function proposeOracleChange(address asset, string calldata info, address newOracle) onlyOwner external override returns (uint256) {
    return IAsset(asset).proposeOracleChange(info, newOracle);
  }

  function proposeDissolution(address asset, string calldata info, address purchaser,
                              address token, uint256 purchaseAmount) onlyOwner external override returns (uint256) {
    IERC20(token).transferFrom(msg.sender, address(this), purchaseAmount);
    return IAsset(asset).proposeDissolution(info, purchaser, token, purchaseAmount);
  }
}
