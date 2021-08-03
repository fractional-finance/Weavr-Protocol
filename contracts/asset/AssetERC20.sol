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
  uint256 public shares;

  bool public override dissolved;

  struct Checkpoint {
    uint256 block;
    uint256 balance;
  }
  mapping(address => Checkpoint[]) private _checkpoints;

  struct Distribution {
    IERC20 token;
    uint256 amount;
    uint256 block;
  }
  Distribution[] private _distributions;
  mapping(address => mapping(uint256 => bool)) public override claimed;

  constructor(
    address _platform,
    uint256 _nft,
    uint256 shares_
  ) ERC20("Fabric Asset", "FBRC-A") AssetWhitelist(IPlatform(platform).whitelist()) {
    require(shares <= ~uint128(0), "Asset: Too many shares");

    platform = _platform;
    nft = _nft;
    shares = shares_;
  }

  function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8) {
      return 0;
  }

  function onERC721Received(address operator, address, uint256 tokenID, bytes calldata) external override returns (bytes4) {
    // Confirm the correct NFT is being locked in
    require(msg.sender == platform);
    require(tokenID == nft);

    _transferOwnership(operator);
    _setWhitelisted(operator, bytes32(0));

    // Only run if this the original NFT; not a re-issue from a platform change
    if (totalSupply() == 0) {
      // Mint the shares
      ERC20._mint(operator, shares);
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

  function balanceOfAtHeight(address person, uint256 height) public view returns (uint256) {
    // Only run when the balances have finalized; prevents flash loans from being used
    require(height < block.number);

    // No balance or earliest balance was after specified height
    if ((_checkpoints[person].length == 0) || (_checkpoints[person][0].block > height)) {
      return 0;
    }

    // Most recent checkpoint is accurate
    if (_checkpoints[person][_checkpoints[person].length - 1].block <= height) {
      return _checkpoints[person][_checkpoints[person].length - 1].balance;
    }

    // Binary search for the applicable checkpoint
    // Choose the bottom of the median
    uint i = (_checkpoints[person].length / 2) - 1;
    // Look for the most recent checkpoint before this block
    // i + 1 is guaranteed to exist as it is never the most recent checkpoint
    // In the case of a single checkpoint, it IS the most recent checkpoint, and therefore would've been caught above
    while (!((_checkpoints[person][i].block <= height) && (_checkpoints[person][i + 1].block > height))) {
      if (_checkpoints[person][i].block < height) {
        // Move up
        // Will never move up to the most recent checkpoint as 1 (the final step) / 2 is 0
        i += (_checkpoints[person].length - i) / 2;
      } else {
        // Move down
        i = i / 2;
      }
    }
    return _checkpoints[person][i].balance;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    require(whitelisted(to));

    // Update the checkpoints
    if ((_checkpoints[from].length == 0) || (_checkpoints[from][_checkpoints[from].length - 1].block != block.number)) {
      _checkpoints[from].push(Checkpoint(block.number, 0));
    }
    _checkpoints[from][_checkpoints[from].length - 1].balance = balanceOf(from) - amount;

    if ((_checkpoints[to].length == 0) || (_checkpoints[to][_checkpoints[to].length - 1].block != block.number)) {
      _checkpoints[to].push(Checkpoint(block.number, 0));
    }
    _checkpoints[to][_checkpoints[to].length - 1].balance = balanceOf(to) + amount;
  }

  function _distribute(IERC20 token, uint256 amount) internal {
    _distributions.push(Distribution(token, amount, block.number));
    emit Distributed(address(token), amount);
  }

  function distribute(address token, uint256 amount) external override {
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    _distribute(IERC20(token), amount);
  }

  function claim(address person, uint256 id) external override {
    require(!claimed[person][id]);
    claimed[person][id] = true;
    // Divides first in order to make sure everyone is paid, even if some dust is left in the contract
    // Should never matter due to large decimal quantity of tokens and comparatively low share quantity
    uint256 amount = _distributions[id].amount / shares * balanceOfAtHeight(person, _distributions[id].block);
    require(amount != 0);
    _distributions[id].token.transfer(person, amount);
    emit Claimed(person, id, amount);
  }
}
