// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../interfaces/auction/IAuction.sol";

contract Auction is IAuction {
  using SafeERC20 for IERC20;

  mapping(address => uint256) private _tokenBalances;

  uint256 private _nextID;
  struct AuctionStruct {
    address token;
    address traded;
    address seller;
    uint256 amount;
    address bidder;
    uint256 bid;
    uint256 start;
    uint256 length;
    uint256 end;
  }
  mapping(uint256 => AuctionStruct) private _auctions;

  mapping(address => mapping(address => uint256)) public override balances;

  // Not vulnerable to re-entrancy, despite being a balance based amount calculation,
  // as it's not before-after. It's stored-current. While someone could re-enter
  // before hand (assuming ERC777 which we don't use), that would cause the first
  // executed transfer to be treated as the sum and every other transfer to be treated as 0
  function getTransferred(address token) private returns (uint256 transferred) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    transferred = balance - _tokenBalances[token];
    _tokenBalances[token] = balance;
  }

  function listTransferred(address token, address traded, address seller, uint256 start, uint256 length) public override {
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

    _auctions[_nextID] = AuctionStruct(token, traded, seller, amount, address(0), 0, start, length, start + length);
    emit NewAuction(_nextID, token, seller, traded, amount, start);
    _nextID++;
  }

  function list(address token, address traded, uint256 amount, uint256 start, uint256 length) external override {
    // Could re-enter here, yet the final call (which executes first) to list (or bid)
    // will be executed with sum(transferred) while every other instance will execute with 0
    // (or whatever value was transferred on top, yet that would be legitimately and newly transferred)
    // Not exploitable
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    listTransferred(token, traded, msg.sender, start, length);
  }

  function bid(uint256 id, uint256 bidAmount) external override {
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
    IERC20(auction.traded).safeTransferFrom(msg.sender, address(this), bidAmount);
    bidAmount = getTransferred(auction.traded);

    // Check the bid is greater than the current bid
    // It would not be either due to fee on transfer or if the above external call
    // re-entered into list/listTransferred/bid
    if (bidAmount <= auction.bid) {
      revert BidTooLow(bidAmount, auction.bid);
    }

    // Make sure they're whitelisted and can actually receive the funds if they win the auction
    if (!IWhitelist(auction.token).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    // Return funds
    // Uses an internal mapping in case the transfer back fails for whatever reason,
    // preventing further bids and enabling a cheap win
    balances[auction.traded][auction.bidder] += auction.bid;

    // If this is a bid near the end of the auction, extend it
    // Only extend it until twice the auction length to prevent DoS attacks however
    // While this would be mutual (auctioneer doesn't get paid, bidder traps their funds),
    // there may still be sufficient incentive to do so
    uint256 newEnd = block.timestamp + (1 days);
    uint256 maxEnd = auction.start + (auction.length * 2);
    if (newEnd > maxEnd) {
      newEnd = maxEnd;
    }
    if (newEnd > auction.end) {
      auction.end = newEnd;
    }

    // Update the bidder and bid
    auction.bidder = msg.sender;
    auction.bid = bidAmount;
    emit Bid(id, auction.bidder, auction.bid);
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
        // In a try/catch to ensure this auction completes no matter what
        // This is the only external call in this function
        try IFrabricERC20(auction.token).burn(auction.amount) {} catch {}
        _tokenBalances[auction.token] = IERC20(auction.token).balanceOf(address(this));
      } else {
        balances[auction.token][auction.seller] += auction.amount;
      }
      return;
    }

    // Else, transfer to the bidder
    balances[auction.token][auction.bidder] += auction.amount;
    balances[auction.traded][auction.seller] += auction.bid;

    emit AuctionCompleted(id);
  }

  function withdraw(address token, address trader) external override {
    uint256 amount = balances[token][trader];
    balances[token][trader] = 0;
    // balances has already been cleared. While someone could try to manipulate _tokenBalances here,
    // see the comment in complete for why this is pointless
    // The more important note is that if the contract is in deficit, this will wipe that deficit
    // The contract should never be in deficit unless an ERC20 which wipes its balance to some degree is used
    // It's an insane edge case where this would be technically valid
    // There's also no way deficits being cleared would trigger this contract to assign
    // funds which don't exist, making it secure
    IERC20(token).safeTransfer(trader, amount);
    _tokenBalances[token] = IERC20(token).balanceOf(address(this));
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
