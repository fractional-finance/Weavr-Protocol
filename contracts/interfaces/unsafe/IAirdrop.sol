// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

interface IAirdrop {
    event ClaimRedeemed(uint256 amount, address claimant);
    event BurnedTokens(uint256 amount);

    function claim() external;

    function viewClaim(address claimant) external view returns (uint256);

    function expire() external;

    error Expired();
    error StillActive();
    error AlreadyClaimed(address claimant);
    error DifferentLengths(uint256 lengthA, uint256 lengthB);
}
