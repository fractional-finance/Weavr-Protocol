// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../erc20/FrabricWhitelist.sol";
import "../interfaces/thread/IThreadDeployer.sol";

import "../interfaces/dao/IDAO.sol";
import "../interfaces/frabric/IFrabric.sol";

contract TestFrabric is FrabricWhitelist {
  // Used by the Thread to determine how long to delay enabling Upgrade proposals for
  function votingPeriod() external pure returns (uint256) {
    return (2 weeks);
  }

  // Contracts ask for the erc20 just as its the whitelist
  // That's why this contract is a whitelist even when the Frabric isn't
  function erc20() external view returns (address) {
    return address(this);
  }

  mapping(address => IFrabricCore.GovernorStatus) public governor;

  function whitelist(address person) external {
    _setWhitelisted(person, bytes32("0x01"));
  }

  function remove(address person) external {
    _setRemoved(person);
  }

  function deployThread(
    address threadDeployer,
    uint8 variant,
    string memory name,
    string memory symbol,
    bytes32 descriptor,
    address _governor,
    address tradeToken,
    uint256 target
  ) external {
    IThreadDeployer(threadDeployer).deploy(
      variant,
      name,
      symbol,
      descriptor,
      _governor,
      abi.encode(tradeToken, target)
    );
  }

  function setGovernor(address person, IFrabricCore.GovernorStatus status) external {
    governor[person] = status;
  }

  constructor() Composable("Frabric") initializer {
    __Composable_init("Frabric", false);
    __FrabricWhitelist_init(address(0));
    supportsInterface[type(IDAOCore).interfaceId] = true;
    supportsInterface[type(IFrabricCore).interfaceId] = true;
  }
}
