// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IDividendERC20.sol";
import "./IFrabricWhitelist.sol";
import "./IIntegratedLimitOrderDEX.sol";

interface IFrabricERC20 {
  function mintable() external view returns (bool);
  function auction() external view returns (address);

  function mint(address to, uint256 amount) external;
  function burn(uint256 amount) external;
  function remove(address person) external;

  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;

  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;
}

interface IFrabricERC20Sum is IDividendERC20Sum, IFrabricWhitelistSum, IIntegratedLimitOrderDEXSum, IFrabricERC20 {
  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool mintable,
    address parentWhitelist,
    address dexToken,
    address auction
  ) external;
}

error SupplyExceedsUInt112(uint256 supply);
error NotMintable();
error CurrentlyPaused();
error BalanceLocked(uint256 balanceAfterTransfer, uint256 lockedBalance);
