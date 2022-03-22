// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

interface IThreadDeployer {
  event Thread(
    address indexed agent,
    address indexed tradeToken,
    address erc20,
    address thread,
    address crowdfund
  );

  function crowdfundProxy() external view returns (address);
  function erc20Beacon() external view returns (address);
  function threadBeacon() external view returns (address);
  function auction() external view returns (address);

  function lockup(address erc20) external view returns (uint256);

  function initialize(
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon,
    address auction
  ) external;

  function validate(uint256 varaint, bytes calldata data) external pure;

  function deploy(
    uint256 varaint,
    address agent,
    string memory name,
    string memory symbol,
    bytes calldata data
  ) external;
}

error UnknownVariant(uint256 id);
error NonStaticDecimals(uint8 beforeDecimals, uint8 afterDecimals);
error TimelockNotExpired(address token, uint256 time, uint256 lockedUntil);
