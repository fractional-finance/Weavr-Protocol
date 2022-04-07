// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface IThreadDeployer is IComposable {
  event Thread(
    uint8 indexed variant,
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
  function timelock() external view returns (address);

  function validate(uint8 variant, bytes calldata data) external view;

  function deploy(
    uint8 variant,
    address agent,
    string memory name,
    string memory symbol,
    bytes calldata data
  ) external;

  function recover(address erc20) external;
  function claimTimelock(address erc20) external;
}

interface IThreadDeployerInitializable is IThreadDeployer {
  function initialize(
    address crowdfundProxy,
    address erc20Beacon,
    address threadBeacon,
    address auction,
    address timelock
  ) external;
}

error UnknownVariant(uint256 id);
error NonStaticDecimals(uint8 beforeDecimals, uint8 afterDecimals);
