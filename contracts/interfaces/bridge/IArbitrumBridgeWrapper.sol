pragma solidity ^0.8.11;

interface IArbitrumBridgeWrapper {
  function receiveFromBridge(uint256 id, address from, address to, bytes calldata data) external;
}
