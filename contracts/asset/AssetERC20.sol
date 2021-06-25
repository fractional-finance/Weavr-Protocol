// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../modifiers/Ownable.sol";
import "./AssetWhitelist.sol";
import "./IntegratedLimitOrderDex.sol";
import "../interfaces/asset/IAssetERC20.sol";

import "../interfaces/platform/IPlatform.sol";

contract AssetERC20 is IAssetERC20, Ownable, ERC20, AssetWhitelist, IntegratedLimitOrderDex {
  address public override platform;
  uint256 public override nft;
  uint256 private _shares;

  bool public override dissolved;

  address public override dividendToken;

  constructor(
    address _platform,
    uint256 _nft,
    uint256 shares
  ) ERC20("Fabric Asset", "FBRC-A") AssetWhitelist(IPlatform(platform).whitelist()) {
    require(shares <= ~uint128(0), "Asset: Too many shares");

    platform = _platform;
    nft = _nft;
    _shares = shares;
  }

  function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8) {
      return 0;
  }

  function onERC721Received(address operator, address, uint256 tokenID, bytes calldata) external override returns (bytes4) {
    // Confirm the correct NFT is being locked in
    require(msg.sender == platform);
    require(tokenID == nft);

    _setWhitelisted(operator, bytes32(0));

    // Only run if this the original NFT; not a re-issue from a platform change
    if (totalSupply() == 0) {
      // Mint the shares
      ERC20._mint(operator, _shares);
    }

    return IERC721Receiver.onERC721Received.selector;
  }

  function setWhitelisted(address person, bytes32 dataHash) external override onlyOwner {
    _setWhitelisted(person, dataHash);
  }

  function globallyAccept() external override onlyOwner {
    _globallyAccept();
  }

  function pause() external override onlyOwner {
    _pause();
  }

  function unpause() external override onlyOwner {
    require(!dissolved);
    _unpause();
  }

  function _dissolved() internal {
    dissolved = true;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    require(whitelisted(to));

    uint256 fromBalance = balanceOf(from);
    uint256 toBalance = balanceOf(to);
  }

  function _distribute(IERC20 token, uint256 amount) internal {
    require(false); // TODO
    emit Distributed(token, amount);
  }

  function distribute(address token, uint256 amount) external override {
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    _distribute(IERC20(token), amount);
  }
}
