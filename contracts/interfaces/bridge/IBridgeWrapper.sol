pragma solidity ^0.8.11;

interface IBridgeWrapper {
  event NewBridgeTransaction(uint256 indexed id, address indexed to, bytes data);
  event BridgeTransactionExecuted(uint256 indexed id);
  function sendToBridge(address to, bytes calldata data) external;
}
