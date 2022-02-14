// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../modifiers/Ownable.sol";
import "../interfaces/platform/IFactory.sol";

contract Factory is Ownable, IFactory {
  address public implementation;

  function initialize(address _implementation) external override initializer {
    __Ownable_init(msg.sender);
    implementation = _implementation;
  }

  constructor() {
    __Ownable_init(address(0));
  }


  function deploy(bytes memory data) external onlyOwner returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, address(this), data);
    proxy.changeAdmin(address(proxy));
    emit Deployed(implementation, address(proxy));
    return address(proxy);
  }
}
