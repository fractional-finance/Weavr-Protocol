// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../lists/IFrabricWhitelistExposed.sol";

interface IFrabricERC20 is IFrabricWhitelistExposed {
  event Distributed(address indexed token, uint256 amount);
  event Claimed(address indexed person, uint256 indexed id, uint256 amount);

  function mintable() external view returns (bool);
  function claimedDistribution(address person, uint256 id) external view returns (bool);

  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    bool mintable,
    address parentWhitelist,
    address dexToken
  ) external;

  function mint(address to, uint256 amount) external;

  function setParentWhitelist(address whitelist) external;
  function setWhitelisted(address person, bytes32 dataHash) external;
  function globallyAccept() external;

  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;

  function distribute(address token, uint256 amount) external;
  function claim(address person, uint256 id) external;
}
