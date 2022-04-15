// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IDistributionERC20.sol";
import "./IFrabricWhitelist.sol";
import "./IIntegratedLimitOrderDEX.sol";

interface IRemovalFee {
  function removalFee(address person) external view returns (uint8);
}

interface IFrabricERC20 is IDistributionERC20, IFrabricWhitelist, IRemovalFee, IIntegratedLimitOrderDEX {
  event Freeze(address indexed person, uint64 until);
  event Removal(address indexed person, uint256 balance);

  function mintable() external view returns (bool);
  function auction() external view returns (address);
  function frozenUntil(address person) external view returns (uint64);

  function mint(address to, uint256 amount) external;
  function burn(uint256 amount) external;
  function freeze(address person, uint64 until) external;
  function triggerRemoval(address person) external;

  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;
  function remove(address participant, uint8 fee) external;

  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;
}

interface IFrabricERC20Initializable is IFrabricERC20 {
  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool mintable,
    address parentWhitelist,
    address tradedToken,
    address auction
  ) external;
}

error SupplyExceedsUInt112(uint256 supply);
error NotMintable();
error Frozen(address person);
error NothingToRemove(address person);
// Not Paused due to an overlap with the event
error CurrentlyPaused();
error BalanceLocked(uint256 balanceAfterTransfer, uint256 lockedBalance);
