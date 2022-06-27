// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/erc20/IFrabricWhitelist.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../common/Composable.sol";

import "../interfaces/erc20/IAuction.sol";

/**
 * @title Auction contract
 * @author Fractional Finance
 * @notice Implements an Auction house for ERC20s
 */
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

  /// @notice Mapping of coin -> user -> balance
  mapping(address => mapping(address => uint256)) public override balances;

  function initialize() external override initializer {
    __ReentrancyGuard_init();
    __Composable_init("Auction", false);
    supportsInterface[type(IAuctionCore).interfaceId] = true;
    supportsInterface[type(IAuction).interfaceId] = true;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Auction") initializer {}

  /**
   * @notice Create a new auction or batch of auctions
   * @param seller Auction seller address
   * @param _token Address of token being sold
   * @param _traded Address of token used for payment
   * @param _amount Amount of tokens being sold
   * @param batches Number of batches to execute the auction in
   * @param start Absolute start time in seconds. Will be set to current time if a past value is provided
   * @param length Auction length in seconds
   * @return id ID of newly created auction
   */
  function list(
    address seller,
    address _token,
    address _traded,
    uint256 _amount,
    uint8 batches,
    uint64 start,
    uint32 length
  ) external override nonReentrant returns (uint256 id) {
    // Require the caller to either be the token itself, forcing a sale, or the
    // seller
    if ((msg.sender != _token) && (msg.sender != seller)) {
      revert Unauthorized(msg.sender, seller);
    }

    // Traditionally vulnerable pattern, hence nonReentrant
    // You can call complete/withdraw during this yet that'd solely decrease the
    // balance, which isn't advantageous
    uint256 startBal = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransferFrom(seller, address(this), _amount);
    _amount = IERC20(_token).balanceOf(address(this)) - startBal;
    if (_amount == 0) {
      revert ZeroAmount();
    }

    // If amount is microscopic, list it in a single batch
    // This following line also prevents batches from equaling 0
    uint256 batchAmount = _amount / batches;
    if (batchAmount == 0) {
      batches = 1;
    }

    // If a start wasn't specified (or has already passed), use now
    if (start < block.timestamp) {
      start = uint64(block.timestamp);
    }

    // Use a single event to save on gas
    emit Auctions(_nextID, seller, _token, _traded, _amount, batches, start, length);

    for (uint256 i = 0; i < batches; i++) {
      // Could technically be further optimized by moving this outside the loop
      // with a duplicated loop body. Not worth it
      if (i == (batches - 1)) {
        // Correct for any rounding errors
        batchAmount = _amount;
      }

      AuctionStruct storage auction = _auctions[_nextID + i];
      auction.seller = seller;
      auction.token = _token;
      auction.traded = _traded;
      auction.amount = batchAmount;
      auction.start = start;
      auction.length = length;
      auction.end = auction.start + length;

      _amount -= batchAmount;
      start += length;
    }

    id = _nextID;
    _nextID += batches;
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
  function notWhitelisted(address _token, address person) private view returns (bool) {
    return (
      // If this contract doesn't support the IFrabricWhitelistCore interface,
      // return false, meaning they're not not whitelisted (meaning they are,
      // as contracts without whitelists behave as if everyone is whitelisted)
      _token.supportsInterface(type(IFrabricWhitelistCore).interfaceId) &&
      // If there is a whitelist and this person isn't whitelisted however,
      // return true so we can error
      (!IFrabricWhitelistCore(_token).whitelisted(person))
    );
  }

  /// @notice Place a bid on an auction
  /// @param id ID of the auction to bid on
  /// @param bidAmount Bid size
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

  /// @notice Complete an auction
  /// @param id Auction ID to be completed
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
        try IFrabricERC20(auction.token).burn(auction.amount) {} catch {
          emit BurnFailed(auction.token, auction.amount);
        }
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


  /// @notice Withdraw token balance of a user (`trader`)
  /// @param _token Address of the token to be withdrawn
  /// @param trader Address of the user to have balance of withdrawn
  function withdraw(address _token, address trader) external override {
    uint256 _amount = balances[_token][trader];
    balances[_token][trader] = 0;
    IERC20(_token).safeTransfer(trader, _amount);
  }

  // These functions will only work for auctions which have yet to complete

  /**
   * @notice Check if an auction is currently active
   * @param id ID of the auction to be checked
   * @return bool true if auction is active, false otherwise
   */
  function active(uint256 id) external view override returns (bool) {
    return (_auctions[id].start <= block.timestamp) && (block.timestamp <= _auctions[id].end);
  }

  // We could expose start/length/seller here, yet we want to encourage using
  // the event API as that will always provide that info while this will solely
  // provide it while the auction is active. This is the data which may have
  // value on chain

  /// @notice Get the token being sold of the active auction with ID `id`
  /// @param id ID of auction to be queried
  /// @return address Token being sold
  function token(uint256 id) external view override returns (address) {
    return _auctions[id].token;
  }

  /// @notice Get the token used to bid on the active auction with ID `id`
  /// @param id ID of auction to be queried
  /// @return address Token used to bid
  function traded(uint256 id) external view override returns (address) {
    return _auctions[id].traded;
  }

  /// @notice Get the amount of tokens being sold in the active auction with ID `id`
  /// @param id ID of auction to be queried
  /// @return uint256 Amount of tokens being sold
  function amount(uint256 id) external view override returns (uint256) {
    return _auctions[id].amount;
  }

  /// @notice Get the current highest bidder of auction with ID `id`
  /// @param id ID of the auction to be queried
  /// @return address Current highest bidder for auction with ID `id`
  function highBidder(uint256 id) external view override returns (address) {
    return _auctions[id].bidder;
  }

  /// @notice Get the high bid amount for auction with ID `id`
  /// @param id ID of auction to be queried
  /// @return uint256 High bid amount of auction with ID `id`
  function highBid(uint256 id) external view override returns (uint256) {
    return _auctions[id].bid;
  }

  /// @notice Get the end time for auction with ID `id`
  /// @param id ID of auction to be queried
  /// @return uint64 Currently scheduled end time in seconds for auction with ID `id`
  function end(uint256 id) external view override returns (uint64) {
    return _auctions[id].end;
  }
}
