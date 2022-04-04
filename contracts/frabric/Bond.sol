// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../erc20/DividendERC20.sol";
import "../interfaces/frabric/IFrabric.sol";

import "../interfaces/frabric/IBond.sol";

// Enables bonding a (presumably) Uniswap v2 LP token
// Stablecoin - Utility token LP will promote a healthy market and enable trivially determining USD bond amount
// In the future, this will allow on-chain bond value calculation
// Combined with property prices (already partially on-chain thanks to Crowdfunds),
// this could enable unbond to no longer be handled by the DAO yet automatically
// allowed as long as a set collateralization ratio is maintained

// Emits a DividendERC20 for dividend functionality (as expected) and so Governors have a reminder of their Bond quantity on Etherscan

contract Bond is OwnableUpgradeable, DividendERC20, IBondInitializable {
  using SafeERC20 for IERC20;

  address public override usd;
  address public override bondToken;

  bool private _burning;

  function initialize(address _usd, address _bondToken) external override initializer {
    __Ownable_init();
    __DividendERC20_init("Frabric Bond", "bFBRC");

    __Composable_init("Bond", false);
    supportsInterface[type(OwnableUpgradeable).interfaceId] = true;
    supportsInterface[type(IBond).interfaceId] = true;

    // Tracks USD now to enable bond value detection in the future without shifting storage
    // Minor forethought that doesn't really matter yet still advantageous
    usd = _usd;
    bondToken = _bondToken;

    _burning = false;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Bond") initializer {}

  function _beforeTokenTransfer(address from, address, uint256) internal view override {
    // from == address(0) means it's being minted
    // _burning means it's being burnt
    // These are the only valid reasons this token should be transferred and these
    // conditions cannot be replicated outside of those cases
    if ((from != address(0)) && (!_burning)) {
      revert BondTransfer();
    }
  }

  function bond(uint256 amount) external override {
    if (IFrabric(owner()).governor(msg.sender) != IFrabric.GovernorStatus.Active) {
      revert NotActiveGovernor(msg.sender, IFrabric(owner()).governor(msg.sender));
    }
    // Safe usage since Uniswap v2 tokens aren't fee on transfer nor 777
    IERC20(bondToken).safeTransferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, amount);
    emit Bond(msg.sender, amount);
  }

  function _burn(address governor, uint256 amount) internal override onlyOwner {
    _burning = true;
    super._burn(governor, amount);
    _burning = false;
  }

  // If the governor isn't active, this could simply allow a full unbond
  // This creates social engineering attacks where it's proposed to remove a malicious governor
  // and the community, thinking that's beneficial, votes on it before slashing them
  function unbond(address governor, uint256 amount) external override onlyOwner {
    _burn(governor, amount);
    emit Unbond(governor, amount);
    IERC20(bondToken).safeTransfer(governor, amount);
  }

  function slash(address governor, uint256 amount) external override onlyOwner {
    _burn(governor, amount);
    emit Slash(governor, amount);
    IERC20(bondToken).safeTransfer(owner(), amount);
  }

  function recover(address token) external override {
    if (token == bondToken) {
      revert RecoveringBond();
    }
    IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
  }
}
