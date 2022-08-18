// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

library errors {
    error UnhandledEnumCase(string label, uint256 enumValue);
    error ZeroPrice();
    error ZeroAmount();

    error UnsupportedInterface(address contractAddress, bytes4 interfaceID);

    error ExternalCallFailed(address called, bytes4 selector, bytes error);

    error Unauthorized(address caller, address user);
    error Replay(uint256 nonce, uint256 expected);

}