// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import "../modifiers/IOwnable.sol";
import "./IAssetWhitelist.sol";
import "./IIntegratedLimitOrderDex.sol";

interface IAssetERC20 is IOwnable, IERC20, IERC20Metadata, IERC721Receiver, IAssetWhitelist, IIntegratedLimitOrderDex {
  event Distributed(address indexed token, uint256 amount);
  event Claimed(address indexed person, uint256 indexed id, uint256 amount);

  function platform() external view returns (address);
  function nft() external view returns (uint256);
  function dissolved() external view returns (bool);
  function claimed(address person, uint256 id) external view returns (bool);

  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;

  function pause() external;
  function unpause() external;

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}
