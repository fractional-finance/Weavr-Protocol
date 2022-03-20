// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../erc20/DividendERC20.sol";
import "../interfaces/frabric/IFrabric.sol";

import "../interfaces/bond/IBond.sol";

// Enables bonding a Uniswap v2 LP token
// Stablecoin - Utility token LP will promote a healthy market and enable trivially determining USD bond amount
// In the future, this will allow on-chain bond value calculation
// Combined with property prices (already partially on-chain thanks to Crowdfunds),
// this could enable unbond to no longer be handled by the DAO yet automatically
// allowed as long as a set collateralization ratio is maintained

// Emits a DividendERC20 for dividend functionality (as expected) and so Governors have a reminder of their Bond quantity on Etherscan

contract Bond is OwnableUpgradeable, DividendERC20, IBond {
  using SafeERC20 for IERC20;

  address public override usd;
  address public override token;

  bool internal _burning;

  function initialize(address _usd, address _token) external initializer {
    __Ownable_init();
    __DividendERC20_init("Frabric Bond", "bFBRC");

    usd = _usd;
    token = _token;

    // Verify the specified bond token actually uses this USD token on one side
    require((IUniswapV2Pair(token).token0() == usd) || (IUniswapV2Pair(token).token1() == usd), "Bond: Bond LP token wasn't composed with this USD token");

    _burning = false;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function _beforeTokenTransfer(address from, address, uint256) internal view override {
    // from == address(0) means it's being minted
    // _burning means it's being burnt
    // These are the only valid reasons this token should be transferred and these
    // conditions cannot be replicated outside of those cases
    require((from == address(0)) || _burning, "Bond: Token cannot be transferred");
  }

  function bond(uint256 amount) external override {
    require(IFrabric(owner()).governor(msg.sender) == IFrabric.GovernorStatus.Active, "Bond: Bonder isn't an active governor");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, amount);
  }

  function _burn(address bonder, uint256 amount) internal override onlyOwner {
    _burning = true;
    super._burn(bonder, amount);
    _burning = false;
  }

  // If the governor isn't active, this could simply allow a full unbond
  // This creates social engineering attacks where it's proposed to remove a malicious bonder
  // and the community, thinking that's beneficial, votes on it before slashing them
  function unbond(address bonder, uint256 amount) external override onlyOwner {
    _burn(bonder, amount);
    IERC20(token).safeTransfer(bonder, amount);
  }

  function slash(address bonder, uint256 amount) external override onlyOwner {
    _burn(bonder, amount);
    IERC20(token).safeTransfer(owner(),  amount);
  }
}
