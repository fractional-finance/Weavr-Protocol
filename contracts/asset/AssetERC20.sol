// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";

import "./AssetWhitelist.sol";
import "./IntegratedLimitOrderDex.sol";

contract AssetERC20 is Ownable, ERC20, AssetWhitelist, IntegratedLimitOrderDex {
  uint32 public constant INDEX_ID = 0;

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
      abi.encodeWithSelector(_ida.createIndex.selector, _dividendToken, INDEX_ID, ""),
      ""
    );
  }

  function decimals() public pure override returns (uint8) {
      return 0;
  }

  function onERC721Received(address operator, address, uint256 tokenID, bytes calldata) external returns (bytes4) {
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
        INDEX_ID,
        operator,
        uint128(_shares),
        ""
      ),
      ""
    );

    return IERC721Receiver.onERC721Received.selector;
  }

  function distribute(uint256 amount) external {
    (uint256 actual, ) = _ida.calculateDistribution(_dividendToken, address(this), INDEX_ID, amount);
    _dividendToken.transferFrom(msg.sender, address(this), actual);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.distribute.selector,
        _dividendToken,
        INDEX_ID,
        actual,
        ""
      ),
      ""
    );
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    uint128 senderUnits = uint128(balanceOf(sender));
    uint128 recipientUnits = uint128(balanceOf(recipient));

    ERC20._transfer(sender, recipient, amount);

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.updateSubscription.selector,
        _dividendToken,
        INDEX_ID,
        sender,
        senderUnits - uint128(amount),
        ""
      ),
      ""
    );

    _superfluid.callAgreement(
      _ida,
      abi.encodeWithSelector(
        _ida.updateSubscription.selector,
        _dividendToken,
        INDEX_ID,
        recipient,
        recipientUnits + uint128(amount),
        ""
      ),
      ""
    );
  }
}
