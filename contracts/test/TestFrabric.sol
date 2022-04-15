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

  function setWhitelisted(address person, bytes32 dataHash) external {
    _setWhitelisted(person, dataHash);
  }

  function threadDeployDeployer(
    address threadDeployer, 
    uint8 _variant,
    address _agent,
    bytes32 _ipfsHash,
    string memory _name,
    string memory _symbol,
    bytes calldata data) external {
      IThreadDeployer(threadDeployer).deploy(_variant, _name, _symbol, _ipfsHash, _agent, data);
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
