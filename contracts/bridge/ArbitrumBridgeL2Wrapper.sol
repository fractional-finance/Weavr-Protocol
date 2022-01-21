pragma solidity ^0.8.11;

import "../interfaces/bridge/Arbitrum.sol";

import "../interfaces/bridge/IBridgeWrapper.sol";
import "../interfaces/bridge/IArbitrumBridgeWrapper.sol";

import "../interfaces/bridge/IBridgeRecipient.sol";

contract ArbitrumBridgeL2Wrapper is IBridgeWrapper, IArbitrumBridgeWrapper {
  ArbSys constant arbsys = ArbSys(0x0000000000000000000000000000000000000064);

  address public l1Bridge;
  mapping(address => bool) public whitelisted;

  mapping(uint256 => bytes) public pending;
  uint256 public count = 1;
  uint256 public lastExecuted = 0;
  uint256 public lastReceived = 0;

  constructor() {}

  // l1Bridge could be part of the constructor yet it'd mean adding another bool to ensure initialize is only called once
  function initialize(address _l1Bridge, address[] calldata whitelist) external {
    require(l1Bridge == address(0));
    l1Bridge = _l1Bridge;
    for (uint i = 0; i < whitelist.length; i++) {
      whitelisted[whitelist[i]] = true;
    }
  }

  modifier onlyWhitelisted() {
    require(whitelisted[msg.sender], "Not whitelisted");
    _;
  }

  function sendToBridge(address to, bytes calldata data) external override onlyWhitelisted {
    // Encode the count as a UID for this transaction
    pending[count] = abi.encodePacked(count, to, data);
    emit NewBridgeTransaction(count, to, data);
    count++;
  }

  function execute(uint256 id) external {
    uint256 next = lastExecuted + 1;
    require(id <= next);
    if (id == next) {
      lastExecuted = next;
    }

    bytes memory data = pending[id];
    require(data.length != 0, "Transaction doesn't exist");
    arbsys.sendTxToL1(l1Bridge, data);

    emit BridgeTransactionExecuted(id);
  }

  function receiveFromBridge(uint256 id, address from, address to, bytes calldata data) external {
    // We can also call isTopLevelCall here yet msg.sender should be secure to the point of hash security
    require(msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1Bridge));

    uint256 next = lastReceived + 1;
    // Silently return if an old message is sent multiple times
    if (id < next) {
      return;
    }
    // Require this message be in the correct order
    require(id == next);
    lastReceived = next;

    IBridgeRecipient(to).receiveFromBridge(from, data);
  }
}
