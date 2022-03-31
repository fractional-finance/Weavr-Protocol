// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "./IDividendERC20.sol";
import "../lists/IFrabricWhitelist.sol";
import "./IIntegratedLimitOrderDEX.sol";

// Doesn't include Ownable, IERC20, IVotes, and IDividendERC20 due to linearization issues by solc
interface IFrabricERC20 is IFrabricWhitelist, IIntegratedLimitOrderDEX {
  function mintable() external view returns (bool);
  function auction() external view returns (address);

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool mintable,
    address parentWhitelist,
    address dexToken,
    address auction
  ) external;

  function mint(address to, uint256 amount) external;
  function burn(uint256 amount) external;
  function remove(address person) external;

  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;

  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;
}

error SupplyExceedsInt256(uint256 supply);
error NotMintable();
error Whitelisted(address person);
error CurrentlyPaused();
error BalanceLocked(uint256 balanceAfterTransfer, uint256 lockedBalance);
