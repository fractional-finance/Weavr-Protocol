pragma solidity ^0.8.11;

interface IBridgeRecipient {
  function receiveFromBridge(address from, bytes calldata data) external;
}
