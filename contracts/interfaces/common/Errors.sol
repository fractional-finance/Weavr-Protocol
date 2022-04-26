// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

error ZeroPrice();
error ZeroAmount();

error UnsupportedInterface(address contractAddress, bytes4 interfaceID);

error UnhandledEnumCase(string label, uint256 enumValue);

error Unauthorized(address caller, address user);
