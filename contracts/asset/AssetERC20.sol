// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";

import "../modifiers/Ownable.sol";
import "./AssetWhitelist.sol";
import "./IntegratedLimitOrderDex.sol";
import "../interfaces/asset/IAssetERC20.sol";

contract AssetERC20 is IAssetERC20, Ownable, ERC20, AssetWhitelist, IntegratedLimitOrderDex {
  address private _fractionalNFT;
  uint256 private _nftID;
  uint256 private _shares;

  ISuperToken private _dividendToken;
  ISuperfluid private _superfluid;
  IInstantDistributionAgreementV1 private _ida;

  constructor(
    address fractionalNFT,
    uint256 nftID,
    uint256 shares,
    address fractionalWhitelist,
    address dividendToken,
    address superfluid,
    address ida
  ) ERC20("Fabric Asset", "FBRC-A") AssetWhitelist(fractionalWhitelist) {
    require(shares <= ~uint128(0), "Asset: Too many shares");

    _fractionalNFT = fractionalNFT;
    _nftID = nftID;
    _shares = shares;

    _dividendToken = ISuperToken(dividendToken);
    _superfluid = ISuperfluid(superfluid);
    _ida = IInstantDistributionAgreementV1(ida);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(_ida.createIndex.selector, _dividendToken, 0, ""),
      ""
    );
  }

  function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8) {
      return 0;
  }

  function onERC721Received(address operator, address, uint256 tokenID, bytes calldata) external override returns (bytes4) {
    // Confirm the correct NFT is being locked in
    require(msg.sender == _fractionalNFT);
    require(tokenID == _nftID);

    // Mint the shares
    ERC20._mint(operator, _shares);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.updateSubscription.selector,
        _dividendToken,
        0,
        operator,
        uint128(_shares),
        ""
      ),
      ""
    );

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
    _unpause();
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    uint256 fromBalance = balanceOf(from);
    uint256 toBalance = balanceOf(to);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.updateSubscription.selector,
        _dividendToken,
        0,
        from,
        uint128(fromBalance - amount),
        ""
      ),
      ""
    );

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.updateSubscription.selector,
        _dividendToken,
        0,
        to,
        uint128(toBalance + amount),
        ""
      ),
      ""
    );
  }

  function distribute(uint256 amount) external override {
    (uint256 actual, ) = _ida.calculateDistribution(_dividendToken, address(this), 0, amount);
    _dividendToken.transferFrom(msg.sender, address(this), actual);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.distribute.selector,
        _dividendToken,
        0,
        actual,
        ""
      ),
      ""
    );
    emit Distributed(msg.sender, amount);
  }
}
