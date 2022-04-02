// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "../erc20/FrabricWhitelist.sol";
import "../interfaces/thread/IThreadDeployer.sol";

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

  function setWhitelisted(address person, bytes32 dataHash) external {
    _setWhitelisted(person, dataHash);
  }

  function threadDeployDeployer(
    address threadDeployer, 
    uint256 _variant,
    address _agent,
    string memory _name,
    string memory _symbol,
    bytes calldata data) external {
      IThreadDeployer(threadDeployer).deploy(_variant, _agent, _name, _symbol, data);
    }

  constructor() initializer {
    __FrabricWhitelist_init(address(0));
  }
}
