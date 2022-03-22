// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.13;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/lists/IWhitelist.sol";

import "../interfaces/auction/IAuction.sol";

contract Auction is ReentrancyGuardUpgradeable, IAuction {
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
    uint256 end;
  }
  mapping(uint256 => AuctionStruct) internal _auctions;

  // Unlike the DEXRouter which is meant to be static to ensure safety of approvals,
  // this Auction contract is ingrained into the Frabric and Threads. While this
  // will also likely get approvals, its code is controlled by the Frabric, not each
  // Thread, and it needs to be able to evolve with the protocol
  function initialize() external initializer {
    __ReentrancyGuard_init();
  }

  // Not vulnerable to re-entrancy, despite being a balance based amount calculation,
  // as it's not before-after. It's stored-current
  function getTransferred(address token) internal returns (uint256 transferred) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    transferred = balance - balances[token];
    balances[token] = balance;
  }

  function listTransferred(address token, address traded, address seller) public override nonReentrant {
    uint256 amount = getTransferred(token);
    if (amount == 0) {
      revert ZeroAmount();
    }

    // This is only intended to be used with Thread tokens, yet technically its
    // only Thread token reliance is on the whitelist function, as it needs to verify
    // bidders can actually receive the auction's tokens
    // Call whitelist in order to verify we can, preventing auction creation if we can't
    // If list was used, this will cause the tokens to be returned (by virtue of never
    // being transferred). If listTransferred was used, someone sent tokens to a contract
    // when they shouldn't have and now they're trapped. They technically can be recovered
    // with a fake auction using them as a bid, or we could add a recovery function,
    // yet any recovery function would be MEV'd in seconds. It's not worth the complexity
    // Also, instead of ignoring the return value, check it because we're already here
    // It should be noted fallback functions may not error here, and may return true
    // There's only so much we can do
    if (!IWhitelist(token).whitelisted(address(this))) {
      revert NotWhitelisted(address(this));
    }

    _auctions[nextID] = AuctionStruct(token, traded, seller, amount, address(0), 0, block.timestamp + (1 weeks));
    emit NewAuction(nextID, token, seller, traded, amount);
    nextID++;
  }

  function list(address token, address traded, uint256 amount) external override {
    // Could re-enter here, yet the final call (which executes first) to list (or bid)
    // will be executed with sum(transferred) while every other instance will execute with 0
    // (or whatever value was transferred on top, yet that would be legitimately and newly transferred)
    // Not exploitable
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    listTransferred(token, traded, msg.sender);
  }

  function bid(uint256 id, uint256 amount) external override nonReentrant {
    AuctionStruct storage auction = _auctions[id];

    // Check the auction isn't over
    if (block.timestamp > auction.end) {
      revert AuctionOver(block.timestamp, auction.end);
    }

    // Check the amount is greater than the current bid
    if (amount <= auction.bid) {
      revert BidTooLow(amount, auction.bid);
    }

    // Transfer the funds
    IERC20(auction.traded).safeTransferFrom(msg.sender, address(this), amount);
    amount = getTransferred(auction.traded);
    // Check the amount actually transferred is greater than the current bid
    // They would not be either due to fee on transfer or if the above external call
    // re-entered into list/listTransferred. Neither of those are issues so long as this check exists
    // This check should also make non-reentrancy into this function a non-issue, as any competing bid
    // placement won't work unless it was higher than the previous bid, and lower than this one,
    // in which case it'll process without issue
    // All of these functions are still nonReentrant just to err on the side of caution
    if (amount <= auction.bid) {
      revert BidTooLow(amount, auction.bid);
    }

    // Make sure they're whitelisted and can actually receive the funds if they win the auction
    if (!IWhitelist(auction.token).whitelisted(msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    // Return funds
    // If anything does peer in at this time, we don't have any partial state updates to view
    // nonReentrant guarantees safety for updating variables after. Without it, we'd
    // need to cache these and do it last
    IERC20(auction.traded).safeTransfer(auction.bidder, auction.amount);
    balances[auction.traded] = IERC20(auction.traded).balanceOf(address(this));

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

  function complete(uint256 id) external override nonReentrant {
    AuctionStruct memory auction = _auctions[id];
    // Prevents re-entrancy regarding this auction and returns a gas refund
    // While other auctions can still be accessed during re-entry, the only side effect
    // is the fact token balances will be decreased. This means additional funds must be transferred in
    // for list/listTransferred to even work, and since they won't be credited, this is never advantageous
    // Though again, all functions do have nonReentrant just to be safe
    delete _auctions[id];

    if (block.timestamp <= auction.end) {
      revert AuctionActive(block.timestamp, auction.end);
    }

    // If no one bid, return the tokens to the seller
    if (auction.bidder == address(0)) {
      IERC20(auction.token).safeTransfer(auction.seller, auction.amount);
      balances[auction.token] = IERC20(auction.token).balanceOf(address(this));
      return;
    }

    // Else, transfer to the bidder
    IERC20(auction.token).safeTransfer(auction.bidder, auction.amount);
    balances[auction.token] = IERC20(auction.token).balanceOf(address(this));
    IERC20(auction.traded).safeTransfer(auction.seller, auction.bid);
    balances[auction.traded] = IERC20(auction.traded).balanceOf(address(this));

    emit AuctionCompleted(id);
  }

  function auctionActive(uint256 id) external view override returns (bool) {
    return block.timestamp <= _auctions[id].end;
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
