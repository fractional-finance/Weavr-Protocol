// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "../common/Composable.sol";
import "../interfaces/common/IUpgradeable.sol";

contract TestUpgradeable is IUpgradeable, Composable {
  event Triggered(uint256 version, bytes data);

  bool data;

  function validateUpgrade(uint256 _version, bytes calldata _data) public view override {
    if (data) {
      (address x, bytes memory y) = abi.decode(_data, (address, bytes));
      require(_version == version, "1");
      require(x == address(3), "2");
      require(keccak256(y) == keccak256(bytes("Upgrade Data")), "3");
    }
  }

  function upgrade(uint256 _version, bytes calldata _data) external override {
    // The above validate function assumes code validating it's the next version
    // This function is supposed to be a version behind, hence the increment
    version++;
    validateUpgrade(_version, _data);
    emit Triggered(_version, _data);
  }

  constructor(uint256 _version, bool _data) Composable("Auction") {
    supportsInterface[type(IUpgradeable).interfaceId] = true;
    version = _version;
    data = _data;
  }
}
