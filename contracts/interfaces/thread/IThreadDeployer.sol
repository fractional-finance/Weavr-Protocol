// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "../common/IComposable.sol";

interface IThreadDeployer {
  event Thread(
    uint256 indexed variant,
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

  function validate(uint256 varaint, bytes calldata data) external view;

  function deploy(
    uint256 varaint,
    address agent,
    string memory name,
    string memory symbol,
    bytes calldata data
  ) external;

  function recover(address erc20) external;
  function claimTimelock(address erc20) external;
}

interface IThreadDeployerSum is IComposableSum, IThreadDeployer {}

error UnknownVariant(uint256 id);
error NonStaticDecimals(uint8 beforeDecimals, uint8 afterDecimals);
