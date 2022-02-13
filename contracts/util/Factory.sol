// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import "../modifiers/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Factory is Ownable {
  event Deployed(address indexed implementation, address indexed proxy);

  address public implementation;

  constructor(address _implementation) onlyOwner {
    implementation = _implementation;
  }

  function deploy() external onlyOwner returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, address(this), bytes(""));
    proxy.changeAdmin(address(proxy));
    emit Deployed(implementation, address(proxy));
    return address(proxy);
  }
}
