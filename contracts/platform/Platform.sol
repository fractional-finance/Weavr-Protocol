// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import "../modifiers/Ownable.sol";
import "../lists/GlobalWhitelist.sol";

import "../interfaces/asset/IAsset.sol";
import "../interfaces/platform/IFactory.sol";
import "../interfaces/platform/IPlatform.sol";

contract Platform is ERC721Upgradeable, Ownable, GlobalWhitelist, IPlatform {
  uint256 internal _asset = 0;
  uint256 internal _assetDeployer = 0;
  mapping(uint256 => IFactory) internal _assetDeployers;

  function initialize() external initializer {
    __ERC721_init("Fractional Platform", "FRACTIONAL");
    __Ownable_init(msg.sender);
  }

  constructor() {
    __ERC721_init("", "");
    __Ownable_init(address(0));
  }

  function setWhitelisted(address person, bytes32 dataHash) onlyOwner external override {
    _setWhitelisted(person, dataHash);
  }

  function createNFT(string calldata data) onlyOwner external override returns (uint256) {
    _safeMint(msg.sender, _asset);
    emit AssetMinted(_asset, data);
    _asset++;
    return _asset - 1;
  }

  function addAssetDeployer(address deployer) onlyOwner external override {
    _assetDeployers[_assetDeployer] = IFactory(deployer);
    emit AddedAssetDeployer(_assetDeployer, deployer);
    _assetDeployer++;
  }

  function removeAssetDeployer(uint256 deployer) onlyOwner external override {
    _assetDeployers[deployer] = IFactory(address(0));
    emit DisabledAssetDeployer(deployer);
  }

  function deployAsset(uint256 deployer, address oracle, uint256 nft,
                       uint256 shares, string memory symbol) onlyOwner external override returns (address asset) {
    require(address(_assetDeployers[deployer]) != address(0), "Platform: Deployer doesn't exist");
    asset = _assetDeployers[deployer].deploy(abi.encode(IAsset.initialize.selector, address(this), oracle, nft, shares, symbol));
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
