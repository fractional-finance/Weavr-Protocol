// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import "../common/Errors.sol";
import "../common/IComposable.sol";

interface IAuction {
  // Indexes the ID as expected, the token so people can find auctions by the token being sold,
  // and the seller so someone can find their auctions which they need to complete
  event NewAuction(
    uint256 indexed id,
    address indexed token,
    address indexed seller,
    address traded,
    uint256 amount,
    uint256 start
  );
  event Bid(uint256 indexed id, address bidder, uint256 amount);
  event AuctionCompleted(uint256 indexed id);

  function balances(address token, address amount) external returns (uint256);

  function list(address token, address traded, uint256 amount, uint256 start, uint256 time) external;
  function listTransferred(address token, address traded, address seller, uint256 start, uint256 time) external;
  function bid(uint256 id, uint256 amount) external;
  function complete(uint256 id) external;
  function withdraw(address token, address trader) external;

  function auctionActive(uint256 id) external view returns (bool);
  function getCurrentBidder(uint256 id) external view returns (address);
  function getCurrentBid(uint256 id) external view returns (uint256);
  function getEndTime(uint256 id) external view returns (uint256);
}

interface IAuctionSum is IComposableSum, IAuction {}

error AuctionPending(uint256 time, uint256 start);
error AuctionOver(uint256 time, uint256 end);
error BidTooLow(uint256 bid, uint256 currentBid);
error AuctionActive(uint256 time, uint256 end);
