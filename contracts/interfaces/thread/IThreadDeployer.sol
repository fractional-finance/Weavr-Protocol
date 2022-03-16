// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IThreadDeployer {
  function initialize(
    address frabric,
    address _crowdfundProxy,
    address _erc20Beacon,
    address _threadBeacon
  ) external;

  function deploy(
    string memory name,
    string memory symbol,
    address parentWhitelist,
    address agent,
    address raiseToken,
    uint256 target
  ) external;
}
