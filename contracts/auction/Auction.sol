// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";

import "../interfaces/auction/IAuction.sol";

contract Auction is OwnableUpgradeable, IAuction {
  using SafeERC20 for IERC20;

  mapping(address => uint256) public override balances;
  uint256 public override nextID;

  struct AuctionStruct {
    address token;
    address traded;
    address seller;
    uint256 amount;
    address bidder;
    uint256 bid;
    uint256 start;
    uint256 end;
  }
  mapping(uint256 => AuctionStruct) private _auctions;
  mapping(address => mapping(address => uint256)) public override pending;

  // Unlike the DEXRouter which is meant to be static to ensure safety of approvals,
  // this Auction contract is ingrained into the Frabric and Threads. While this
  // will also likely get approvals, its code is controlled by the Frabric, not each
  // Thread, and it needs to be able to evolve with the protocol
  function initialize() external initializer {
    __Ownable_init();
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // Not vulnerable to re-entrancy, despite being a balance based amount calculation,
  // as it's not before-after. It's stored-current. While someone could re-enter
  // before hand (assuming ERC777 which we don't use), that would cause the first
  // executed transfer to be treated as the sum and every other transfer to be treated as 0
  function getTransferred(address token) private returns (uint256 transferred) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    transferred = balance - balances[token];
    balances[token] = balance;
  }

  function listTransferred(address token, address traded, address seller, uint256 start) public override {
    uint256 amount = getTransferred(token);
    if (amount == 0) {
      revert ZeroAmount();
    }

    // This is only intended to be used with Thread tokens, yet technically its
    // only Thread token reliance is on the whitelist function, as it needs to verify
    // bidders can actually receive the auction's tokens
    // Call whitelist in order to verify we can, preventing auction creation if we can't
    // If list was used, this will cause the tokens to be pending (by virtue of never
    // being transferred). If listTransferred was used, someone sent tokens to a contract
    // when they shouldn't have and now they're trapped. They technically can be recovered
    // with a fake auction using them as a bid, or we could add a recovery function,
    // yet any recovery function would be voided via the above fake auction strategy
    // Also, instead of ignoring the return value, check it because we're already here
    // It should be noted fallback functions may not error here, and may return true
    // There's only so much we can do
    if (!IWhitelist(token).whitelisted(address(this))) {
      revert NotWhitelisted(address(this));
    }

    _auctions[nextID] = AuctionStruct(token, traded, seller, amount, address(0), 0, start, block.timestamp + (1 weeks));
    emit NewAuction(nextID, token, seller, traded, amount, start);
    nextID++;
  }

  function list(address token, address traded, uint256 amount, uint256 start) external override {
    // Could re-enter here, yet the final call (which executes first) to list (or bid)
    // will be executed with sum(transferred) while every other instance will execute with 0
    // (or whatever value was transferred on top, yet that would be legitimately and newly transferred)
    // Not exploitable
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    listTransferred(token, traded, msg.sender, start);
  }

  function bid(uint256 id, uint256 amount) external override {
    AuctionStruct storage auction = _auctions[id];

    // Check the auction has started
    if (block.timestamp < auction.start) {
      revert AuctionPending(block.timestamp, auction.start);
    }

    // Check the auction isn't over
    if (block.timestamp > auction.end) {
      revert AuctionOver(block.timestamp, auction.end);
    }

    // Transfer the funds
    // While this very easily could re-enter, the only checks so far have been on
    // block.timestamp which will be static against start/end which will also be static
    // (technically, end may be extended, yet that wouldn't change the above behavior)
    // A re-enter could cause multiple bids to execute for this auction, yet no writes have happened yet
    // All amounts would need to be legitimately transferred and the amount transferred is verified to
    // be enough for a new bid below
    IERC20(auction.traded).safeTransferFrom(msg.sender, address(this), amount);
    amount = getTransferred(auction.traded);

    // Check the amount is greater than the current bid
    // It would not be either due to fee on transfer or if the above external call
    // re-entered into list/listTransferred/bid
    if (amount <= auction.bid) {
      revert BidTooLow(amount, auction.bid);
    }

    // Make sure they're whitelisted and can actually receive the funds if they win the auction
    if (!IWhitelist(auction.token).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    // Return funds
    // Uses an internal mapping in case the transfer back fails for whatever reason,
    // preventing further bids and enabling a cheap win
    pending[auction.traded][auction.bidder] += auction.amount;

    // Update the bidder and bid
    auction.bidder = msg.sender;
    auction.amount = amount;
    emit Bid(id, auction.bidder, amount);

    // If this is a bid near the end of the auction, extend it
    uint256 newEnd = block.timestamp + (1 days);
    if (newEnd > auction.end) {
      auction.end = newEnd;
    }
  }

  function complete(uint256 id) external override {
    AuctionStruct memory auction = _auctions[id];
    // Prevents re-entrancy regarding this auction and returns a gas refund
    // While other auctions can still be accessed during re-entry, the only side effect
    // is the fact token balances will be decreased. This means additional funds must be transferred in
    // for list/listTransferred/bid to even work, and since they won't be credited, this is never advantageous
    delete _auctions[id];

    if (block.timestamp <= auction.end) {
      revert AuctionActive(block.timestamp, auction.end);
    }

    // If no one bid, return the tokens to the seller
    // If this auction was the result of a removal, this'll fail because they're not whitelisted
    // Burn their tokens in this case
    if (auction.bidder == address(0)) {
      if (!IWhitelist(auction.token).whitelisted(auction.seller)) {
        IFrabricERC20(auction.token).burn(auction.amount);
        balances[auction.token] = IERC20(auction.token).balanceOf(address(this));
      } else {
        pending[auction.token][auction.seller] += auction.amount;
      }
      return;
    }

    // Else, transfer to the bidder
    pending[auction.token][auction.bidder] += auction.amount;
    pending[auction.traded][auction.seller] += auction.bid;

    emit AuctionCompleted(id);
  }

  function withdraw(address token, address trader) external override returns (uint256) {
    uint256 amount = pending[token][trader];
    pending[token][trader] = 0;
    // pending has already been cleared. While someone could try to manipulate balances here,
    // see the comment in complete for why this is pointless
    IERC20(token).safeTransfer(trader, amount)
    balances[token] = IERC20(token).balanceOf(address(this));
  }

  function auctionActive(uint256 id) external view override returns (bool) {
    return (_auctions[id].start <= block.timestamp) && (block.timestamp <= _auctions[id].end);
  }
  function getCurrentBidder(uint256 id) external view override returns (address) {
    return _auctions[id].bidder;
  }
  function getCurrentBid(uint256 id) external view override returns (uint256) {
    return _auctions[id].bid;
  }
  function getEndTime(uint256 id) external view override returns (uint256) {
    return _auctions[id].end;
  }
}
