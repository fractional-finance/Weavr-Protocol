// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IAuction.sol";

contract Auction is ReentrancyGuardUpgradeable, Composable, IAuctionInitializable {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  uint256 private _nextID;
  struct AuctionStruct {
    // These fields look horrible yet this is perfectly packed
    address token;
    uint64 start;
    uint32 length;
    // 4 bytes left open in this slot
    address traded;
    uint64 end;

    // uint96 amounts would be perfectly packed here and support 70 billion 1e18
    // That would be more than acceptable for all ERC20s worth more than 1 US cent
    // (or if they're worth less, with appropriately shifted decimals)
    // It's also a bit of a micro-optimization that reduces compatibility
    // and could set an unfair, semi-hidden, bid value ceiling
    address seller;
    address bidder;
    uint256 amount;
    uint256 bid;
  }
  mapping(uint256 => AuctionStruct) private _auctions;

  mapping(address => mapping(address => uint256)) public override balances;

  function initialize() external override initializer {
    __ReentrancyGuard_init();
    __Composable_init("Auction", false);
    supportsInterface[type(IAuctionCore).interfaceId] = true;
    supportsInterface[type(IAuction).interfaceId] = true;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Auction") initializer {}

  function list(
    address seller,
    address token,
    address traded,
    uint256 amount,
    uint256 batches,
    uint64 start,
    uint32 length
  ) external override nonReentrant returns (uint256 id) {
    // Require the caller to either be the token itself, forcing a sale, or the
    // seller
    if ((msg.sender != token) && (msg.sender != seller)) {
      revert Unauthorized(msg.sender, seller);
    }

    // Traditionally vulnerable pattern, hence nonReentrant
    // You can call complete/withdraw during this yet that'd solely decrease the
    // balance, which isn't advantageous
    uint256 startBal = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(seller, address(this), amount);
    amount = IERC20(token).balanceOf(address(this)) - startBal;
    if (amount == 0) {
      revert ZeroAmount();
    }

    // If amount is microscopic, list it in a single batch
    // This following line also prevents batches from equaling 0
    uint256 batchAmount = amount / batches;
    if (batchAmount == 0) {
      batches = 1;
    }

    // If a start wasn't specified (or has already passed), use now
    if (start < block.timestamp) {
      start = uint64(block.timestamp);
    }

    for (uint256 i = 0; i < batches; i++) {
      // Could technically be further optimized by moving this outside the loop
      // with a duplicated loop body. Not worth it
      if (i == (batches - 1)) {
        // Correct for any rounding errors
        batchAmount = amount;
      }

      id = _nextID;
      _nextID++;

      AuctionStruct storage auction = _auctions[id];
      auction.seller = seller;
      auction.token = token;
      auction.traded = traded;
      auction.amount = batchAmount;
      auction.start = start + uint64(i * length);
      auction.length = length;
      auction.end = auction.start + length;
      emit Listing(id, seller, token, traded, batchAmount, auction.start, length);

      amount -= batchAmount;
    }
  }

  // If for some reason there's a contract with a screwed up fallback function,
  // or a non-EIP165-compliant supportsInterface function, this may claim no one is ever whitelisted
  // That will prevent all bids and have the auction default, triggering burn to be called
  // This Auction contract therefore defines its scope to only work with ERC20s which:
  // A) Support EIP165
  // B) Don't support EIP165 and don't have a fallback function
  // C) Don't support EIP165 and do have a fallback function which doesn't pass as EIP165 compatible
  // D) Don't support EIP165, do have a fallback function passing as EIP165 compatible, and claim everyone is whitelisted
  // In practice, D should never be hit due to how archaic it is. EIP165 ensures fallback
  // functions which always return true aren't EIP165 compatible as it explicitly tests
  // an invalid interface isn't supported. If they always return false, they also won't be
  // EIP165 compatible
  // If the contract doesn't implement EIP165 and errors here, the ERC165Checker library
  // will return false, preventing the need for a try/catch
  // WETH notably does have a fallback function yet it returns nothing, which means it
  // won't pass as EIP165 compatible

  // This comment is a waste of space yet technically accurate and therefore remains
  function notWhitelisted(address token, address person) private view returns (bool) {
    return (
      // If this contract doesn't support the IWhitelist interface,
      // return false, meaning they're not not whitelisted (meaning they are,
      // as contracts without whitelists behave as if everyone is whitelisted)
      token.supportsInterface(type(IWhitelist).interfaceId) &&
      // If there is a whitelist and this person isn't whitelisted however,
      // return true so we can error
      (!IWhitelist(token).whitelisted(person))
    );
  }

  function bid(uint256 id, uint256 bidAmount) external override nonReentrant {
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
    uint256 start = IERC20(auction.traded).balanceOf(address(this));
    IERC20(auction.traded).safeTransferFrom(msg.sender, address(this), bidAmount);
    bidAmount = IERC20(auction.traded).balanceOf(address(this)) - start;

    // Check the bid is greater than the current bid
    // It would not be either due to fee on transfer or if the above external call
    // re-entered into list/listTransferred/bid
    if (bidAmount <= auction.bid) {
      revert BidTooLow(bidAmount, auction.bid);
    }

    // Make sure they're whitelisted and can actually receive the funds if they win the auction
    if (notWhitelisted(auction.token, msg.sender)) {
      revert NotWhitelisted(msg.sender);
    }

    // Make sure they're not already the high bidder for some reason
    if (auction.bidder == msg.sender) {
      revert HighBidder(msg.sender);
    }

    // Return funds
    // Uses an internal mapping in case the transfer back fails for whatever reason,
    // preventing further bids and enabling a cheap win
    balances[auction.traded][auction.bidder] += auction.bid;

    // If this is a bid near the end of the auction, extend it
    // Only extend it until twice the auction length to prevent DoS attacks however
    // While this would be mutual (auctioneer doesn't get paid, bidder traps their funds),
    // there may still be sufficient incentive to do so
    uint64 newEnd = uint64(block.timestamp) + (1 days);
    uint64 maxEnd = auction.start + (auction.length * 2);
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
    // While other auctions can still be accessed during re-entry, that shouldn't
    // have any side effects
    delete _auctions[id];

    if (block.timestamp <= auction.end) {
      revert AuctionActive(block.timestamp, auction.end);
    }

    // If no one bid, return the tokens to the seller
    // If this auction was the result of a removal, this'll fail because they're not whitelisted
    // Burn their tokens in this case
    if (auction.bidder == address(0)) {
      if (notWhitelisted(auction.token, auction.seller)) {
        // In a try/catch to ensure this auction completes no matter what
        // In the worst case, these funds will be left here forever
        try IFrabricERC20(auction.token).burn(auction.amount) {} catch {}
      } else {
        balances[auction.token][auction.seller] += auction.amount;
      }
    } else {
      // Else, transfer to the bidder
      balances[auction.token][auction.bidder] += auction.amount;
      balances[auction.traded][auction.seller] += auction.bid;
    }

    emit AuctionComplete(id);
  }

  function withdraw(address token, address trader) external override {
    uint256 amount = balances[token][trader];
    balances[token][trader] = 0;
    IERC20(token).safeTransfer(trader, amount);
  }

  function active(uint256 id) external view override returns (bool) {
    return (_auctions[id].start <= block.timestamp) && (block.timestamp <= _auctions[id].end);
  }
  function highestBidder(uint256 id) external view override returns (address) {
    return _auctions[id].bidder;
  }
  function highestBid(uint256 id) external view override returns (uint256) {
    return _auctions[id].bid;
  }
  function end(uint256 id) external view override returns (uint64) {
    return _auctions[id].end;
  }
}
