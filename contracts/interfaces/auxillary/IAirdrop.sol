// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

interface IAirdrop {
    event ClaimRedeemed(uint256 amount, address claimant);
    event ClaimAdded(uint256, address claimant);
    event Deposit(uint256 amount);
    event BurnedTokens(uint256 amount);

    function addClaim(address [] memory claimants, uint256 [] memory amounts) external;

    function claim() external;

    function viewClaim(address claimant) external view returns (uint256);

    function expire() external;

    error Expired();
    error StillActive();
    error AlreadyClaimed(uint256 amount, address claimant);
    error InsufficientFunds(uint256 expected, uint256 real);
    error DifferentLengths(uint256 lengthA, uint256 lengthB);
}
