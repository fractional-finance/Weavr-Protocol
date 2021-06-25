// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../modifiers/IOwnable.sol";
import "./IAssetWhitelist.sol";
import "./IIntegratedLimitOrderDex.sol";

interface IAssetERC20 is IOwnable, IERC20, IERC20Metadata, IERC721Receiver, IAssetWhitelist, IIntegratedLimitOrderDex {
  event Distributed(address token, uint256 amount);

  function platform() external view returns (address);
  function nft() external view returns (uint256);
  function dividendToken() external view returns (address);
  function dissolved() external view returns (bool);

  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;

  function pause() external;
  function unpause() external;

  function distribute(address token, uint256 amount) external;
}
