pragma solidity ^0.8.11;

import "../interfaces/bridge/Arbitrum.sol";

import "../interfaces/bridge/IBridgeWrapper.sol";
import "../interfaces/bridge/IArbitrumBridgeWrapper.sol";

import "../interfaces/bridge/IBridgeRecipient.sol";

contract ArbitrumBridgeL1Wrapper is IBridgeWrapper, IArbitrumBridgeWrapper {
  IInbox public inbox;
  address public l2Bridge;
  mapping(address => bool) public whitelisted;

  mapping(uint256 => bytes) public pending;
  uint256 public count = 1;
  uint256 public lastExecuted = 0;
  uint256 public lastReceived = 0;

  constructor(address _inbox) {
    inbox = IInbox(_inbox);
  }

  // Not part of the constructor due to the fact the L2 bridge is deployed after
  // Whitelisted to remove the possibility of messages from other contracts, malicious or taking advantage
  // Other projects can trivially deploy their own and this does reduce our attack surface
  function initialize(address _l2Bridge, address[] calldata whitelist) external {
    require(l2Bridge == address(0));
    l2Bridge = _l2Bridge;
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
    pending[count] = abi.encodeWithSelector(IArbitrumBridgeWrapper.receiveFromBridge.selector, count, msg.sender, to, data);
    emit NewBridgeTransaction(count, to, data);
    count++;
  }

  function execute(
    uint256 id,
    uint256 maxSubmissionCost,
    uint256 maxGas,
    uint256 gasPriceBid
  ) external payable {
    // This doesn't simply check id == next because some submissions may fail/happen out of order
    // This allows retrying yet ensures future transactions will not be submitted before they have a chance at passing
    // The matching bridge validates it receives these in order
    uint256 next = lastExecuted + 1;
    require(id <= next);
    if (id == next) {
      lastExecuted = next;
    }

    bytes memory data = pending[id];
    require(data.length != 0, "Transaction doesn't exist");
    inbox.createRetryableTicket{value: msg.value}(
      l2Bridge,
      0,
      maxSubmissionCost,
      msg.sender,
      msg.sender,
      maxGas,
      gasPriceBid,
      data
    );

    emit BridgeTransactionExecuted(id);
  }

  function receiveFromBridge(uint256 id, address from, address to, bytes calldata data) external {
    IBridge bridge = inbox.bridge();
    // Check the bridge to prevent a contract in the middle from forging messages
    require(msg.sender == address(bridge));
    IOutbox outbox = IOutbox(bridge.activeOutbox());
    require(outbox.l2ToL1Sender() == l2Bridge);

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
