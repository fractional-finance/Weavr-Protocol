// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/erc20/IERC20Burnable.sol";
import "../interfaces/auxillary/IAirdrop.sol";

contract Airdrop is Ownable, IAirdrop {
    uint64 private _expiryDate;
    bool private _expired;
    address private _token;

    struct Pledge {
        uint256 amount;
        bool available;
    }

    mapping(address => Pledge) private _claims;
    constructor(uint8 daysUntilExpiry, address erc20){
        _expiryDate = uint64(block.timestamp) + (daysUntilExpiry * 1 days);
        _expired = false;
        _token = erc20;
    }

    /*
    * @dev Adds a claim to the airdrop
    * @param claimants An array of the addresses of the claimants
    * @param amounts An array of the amounts of tokens to be claimed
    * @return None
    */

    function addClaim(address [] memory claimants, uint256 [] memory amounts) external onlyOwner {
        if (claimants.length != amounts.length) {
            revert DifferentLengths(claimants.length, amounts.length);
        }
        if (_expired == true) {
            revert Expired();
        }
        for (uint64 i = 0; i < claimants.length; i++) {
            Pledge memory pledge = Pledge(amounts[i], true);
            //If the claimant was already added, lets skip over them without overwriting.
            if (_claims[claimants[i]].amount == 0) {
                _claims[claimants[i]] = pledge;
                emit ClaimAdded(amounts[i], claimants[i]);
            }
        }
    }

    /*
    * @dev Claim your tokens from the airdrop.
    * @notice This function will revert if the airdrop has expired, or if the claimant has already claimed.
    * @notice This function will revert if the airdrop contract does not have enough tokens to fulfill the claim.
    */

    function claim() external {
        if (block.timestamp > _expiryDate) {
            _expired = true;
            revert Expired();
        }
        if (_expired == true) {
            revert Expired();
        }
        Pledge memory pledge = _claims[msg.sender];
        if (pledge.available == false || pledge.amount == 0) {
            revert AlreadyClaimed(pledge.amount, msg.sender);
        }
        if (pledge.amount > IERC20Burnable(_token).balanceOf(address(this))) {
            revert InsufficientFunds(pledge.amount, IERC20Burnable(_token).balanceOf(address(this)));
        }
        IERC20Burnable(_token).transfer(msg.sender, pledge.amount);
        _claims[msg.sender].available = false;
        emit ClaimRedeemed(pledge.amount, msg.sender);
    }

    /**
     * @dev Burns all remaining tokens in the contract.
     * This function can be called by anyone after the expiry date.
     * The Owner can call this function at any time.
     */

    function expire() external {
        if (msg.sender != owner()) {
            if (block.timestamp > _expiryDate) {
                _expired = true;
            }
            if (_expired == false) {
                revert StillActive();
            }
        }
        uint256 balance = IERC20Burnable(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20Burnable(_token).burn(balance);
            emit BurnedTokens(balance);
        }
    }

    /*
    * @dev Returns the expiry date of the airdrop.
    * @return The expiry date of the airdrop.
    */

    function viewClaim(address claimant) external view returns (uint256) {
        if (_claims[claimant].available == false) {
            return 0;
        } else {
            return (_claims[claimant].amount);
        }
    }

}
