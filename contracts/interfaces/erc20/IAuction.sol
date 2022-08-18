// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import {errors} from "../common/Errors.sol";
import "../common/IComposable.sol";

// When someone is removed, each FrabricERC20 will list the removed party's tokens
// for auction. This is done with the following listing API which is separated out
// for greater flexibility in the future
interface IAuctionCore is IComposable {
  // Indexes the ID as expected, the seller so people can find their own auctions
  // which they need to complete, and the token so people can find auctions by the token being sold
  event Auctions(
    uint256 indexed startID,
    address indexed seller,
    address indexed token,
    address traded,
    uint256 total,
    uint8 quantity,
    uint64 start,
    uint32 length
  );

  function list(
    address seller,
    address token,
    address traded,
    uint256 amount,
    uint8 batches,
    uint64 start,
    uint32 length
  ) external returns (uint256 id);
}

interface IAuction is IAuctionCore {
  event Bid(uint256 indexed id, address bidder, uint256 amount);
  event AuctionComplete(uint256 indexed id);
  event BurnFailed(address indexed token, uint256 amount);

  function balances(address token, address amount) external returns (uint256);

  function bid(uint256 id, uint256 amount) external;
  function complete(uint256 id) external;
  function withdraw(address token, address trader) external;

  function active(uint256 id) external view returns (bool);
  // Will only work for auctions which have yet to complete
  function token(uint256 id) external view returns (address);
  function traded(uint256 id) external view returns (address);
  function amount(uint256 id) external view returns (uint256);
  function highBidder(uint256 id) external view returns (address);
  function highBid(uint256 id) external view returns (uint256);
  function end(uint256 id) external view returns (uint64);
}

interface IAuctionInitializable is IAuction {
  function initialize() external;
}

error AuctionPending(uint256 time, uint256 start);
error AuctionOver(uint256 time, uint256 end);
error BidTooLow(uint256 bid, uint256 currentBid);
error HighBidder(address bidder);
error AuctionActive(uint256 time, uint256 end);
