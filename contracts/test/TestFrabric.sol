// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "../erc20/FrabricWhitelist.sol";
import "../interfaces/thread/IThreadDeployer.sol";

import "../interfaces/dao/IDAO.sol";
import "../interfaces/frabric/IBond.sol";
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

  function setParent(address _parent) external override {
    _setParent(_parent);
  }

  function whitelist(address person) external override {
    _whitelist(person);
  }

  function setKYC(address person, bytes32 hash, uint256 nonce) external override {
    _setKYC(person, hash, nonce);
  }

  function remove(address person) external {
    _setRemoved(person);
  }

  function setGovernor(address person, IFrabricCore.GovernorStatus status) external {
    governor[person] = status;
  }

  function unbond(address bond, address _governor, uint256 amount) external {
    IBondCore(bond).unbond(_governor, amount);
  }

  function slash(address bond, address _governor, uint256 amount) external {
    IBondCore(bond).slash(_governor, amount);
  }

  function deployThread(
    address threadDeployer,
    uint8 variant,
    string memory name,
    string memory symbol,
    bytes32 descriptor,
    address _governor,
    address _broker,
    address tradeToken,
    uint112 target
  ) external {
    IThreadDeployer(threadDeployer).deploy(
      variant,
      name,
      symbol,
      descriptor,
      _governor,
      _broker,
      abi.encode(tradeToken, target)
    );
  }

  constructor() Composable("Frabric") initializer {
    __Composable_init("Frabric", false);
    __FrabricWhitelist_init(address(0));
    supportsInterface[type(IDAOCore).interfaceId] = true;
    supportsInterface[type(IFrabricCore).interfaceId] = true;
  }
}
