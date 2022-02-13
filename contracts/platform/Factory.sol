// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../modifiers/Ownable.sol";

contract Factory is Ownable, IFactory {
  address public implementation;

  function initialize(address _implementation) external initializer {
    Ownable.initialize(msg.sender);
    implementation = _implementation;
  }

  constructor() {
    Ownable.initialize(address(0));
  }


  function deploy(bytes memory data) external onlyOwner returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, address(this), data);
    proxy.changeAdmin(address(proxy));
    emit Deployed(implementation, address(proxy));
    return address(proxy);
  }
}
