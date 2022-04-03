// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IAuction.sol";

contract Auction is Initializable, Composable, IAuctionSum {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  mapping(address => uint256) private _tokenBalances;

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
    uint256 amount;
    address bidder;
    uint256 bid;
  }
  mapping(uint256 => AuctionStruct) private _auctions;

  mapping(address => mapping(address => uint256)) public override balances;

  function initialize() external initializer {
    __Composable_init("Auction", false);
    supportsInterface[type(IAuction).interfaceId] = true;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Auction") initializer {}

  // Not vulnerable to re-entrancy, despite being a balance based amount calculation,
  // as it's not before-after. It's stored-current. While someone could re-enter
  // before hand (assuming ERC777 which we don't use), that would cause the first
  // executed transfer to be treated as the sum and every other transfer to be treated as 0
  function getTransferred(address token) private returns (uint256 transferred) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    transferred = balance - _tokenBalances[token];
    _tokenBalances[token] = balance;
  }

  function listTransferred(address token, address traded, address seller, uint64 start, uint32 length) public override {
    uint256 amount = getTransferred(token);
    if (amount == 0) {
      revert ZeroAmount();
    }

    AuctionStruct storage auction = _auctions[_nextID];
    auction.token = token;
    auction.traded = traded;
    auction.seller = seller;
    auction.amount = amount;
    auction.start = start;
    auction.length = length;
    auction.end = start + length;
    emit NewAuction(_nextID, token, seller, traded, amount, start, length);
    _nextID++;
  }

  function list(address token, address traded, uint256 amount, uint64 start, uint32 length) external override {
    // Could re-enter here, yet the final call (which executes first) to list (or bid)
    // will be executed with sum(transferred) while every other instance will execute with 0
    // (or whatever value was transferred on top, yet that would be legitimately and newly transferred)
    // Not exploitable
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    listTransferred(token, traded, msg.sender, start, length);
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
  function notWhitelisted(address token, address person) internal view returns (bool) {
    return (
      // If this contract doesn't support the IFrabricWhitelist interface,
      // return false, meaning they're not not whitelisted (meaning they are,
      // as contracts without whitelists behave as if everyone is whitelisted)
      token.supportsInterface(type(IFrabricWhitelist).interfaceId) &&
      // If there is a whitelist and this person isn't whitelisted however,
      // return true so we can error
      (!IFrabricWhitelist(token).whitelisted(person))
    );
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
    if (notWhitelisted(auction.token, msg.sender)) {
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
      if (notWhitelisted(auction.token, auction.seller)) {
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
