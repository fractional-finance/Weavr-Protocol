// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../interfaces/modifiers/IOwnable.sol";

abstract contract Ownable is IOwnable {
    address private _owner;

    constructor() {
      _owner = msg.sender;
      emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view override returns (address) {
      return _owner;
    }

    modifier onlyOwner() {
      require(owner() == msg.sender, "Ownable: msg.sender != owner");
      _;
    }

    function renounceOwnership() public override onlyOwner {
      _owner = address(0);
        emit OwnershipTransferred(_owner, address(0));
    }

    function _transferOwnership(address newOwner) internal {
      require(newOwner != address(0), "Ownable: new owner is the zero address");
      emit OwnershipTransferred(_owner, newOwner);
      _owner = newOwner;
    }

    function transferOwnership(address newOwner) public override onlyOwner {
      _transferOwnership(newOwner);
    }
}
