// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import "../interfaces/modifiers/IOwnable.sol";

abstract contract Ownable is Initializable, IOwnable {
    address public owner;

    function __Ownable_init(address _owner) internal onlyInitializing {
      owner = _owner;
      emit OwnershipTransferred(address(0), owner);
    }

    // No constructor included as owner will be address(0)

    modifier onlyOwner() {
      require(owner == msg.sender, "Ownable: msg.sender != owner");
      _;
    }

    function renounceOwnership() public override onlyOwner {
      owner = address(0);
      emit OwnershipTransferred(owner, address(0));
    }

    function _transferOwnership(address newOwner) internal {
      require(newOwner != address(0), "Ownable: new owner is the zero address");
      emit OwnershipTransferred(owner, newOwner);
      owner = newOwner;
    }

    function transferOwnership(address newOwner) public override onlyOwner {
      _transferOwnership(newOwner);
    }
}
