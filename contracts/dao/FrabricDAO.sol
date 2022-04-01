// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { SafeERC20Upgradeable as SafeERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC165CheckerUpgradeable as ERC165Checker } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";
import "../interfaces/beacon/IFrabricBeacon.sol";

import "./DAO.sol";

import "../interfaces/dao/IFrabricDAO.sol";

// Implements proposals mutual to both Threads and the Frabric
// This could be merged directly into DAO, as the Thread and Frabric contracts use this
// yet DAO is only used by this
// This offers smaller, more compartamentalized code, and directly integrating the two
// doesn't actually offer any efficiency benefits. The new structs, the new variables, and
// the new code are still needed, meaning it really just inlines _completeProposal
abstract contract FrabricDAO is DAO, IFrabricDAOSum {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  uint256 constant public commonProposalBit = 1 << 255;

  struct Upgrade {
    address beacon;
    address instance;
    address code;
  }
  mapping(uint256 => Upgrade) internal _upgrades;

  struct TokenAction {
    address token;
    address target;
    bool mint;
    uint256 price;
    uint256 amount;
  }
  mapping(uint256 => TokenAction) internal _tokenActions;

  mapping(uint256 => address) internal _removals;

  function __FrabricDAO_init(address _erc20, uint256 _votingPeriod) internal onlyInitializing {
    __DAO_init(_erc20, _votingPeriod);
    supportsInterface[type(IFrabricDAO).interfaceId] = true;
  }

  function proposePaper(string calldata info) external returns (uint256) {
    // No dedicated event as the DAO emits type and info
    return _createProposal(uint256(CommonProposalType.Paper) | commonProposalBit, info);
  }

  // Allowed to be overriden (see Thread for why)
  // Isn't required to be overriden and assumes Upgrade proposals are valid like
  // any other proposal unless overriden
  function _canProposeUpgrade(
    address /*beacon*/,
    address /*instance*/,
    address /*code*/
  ) internal view virtual returns (bool) {
    return true;
  }

  // Allows upgrading itself or any contract owned by itself
  // Specifying any irrelevant beacon will work yet won't have any impact
  // Specifying an arbitrary contract would also work if it has functions/
  // a fallback function which don't error when called
  // Between human review, function definition requirements, and the lack of privileges bestowed,
  // this is considered to be appropriately managed
  function proposeUpgrade(
    address beacon,
    address instance,
    address code,
    string calldata info
  ) external returns (uint256) {
    if (!_canProposeUpgrade(beacon, instance, code)) {
      revert ProposingUpgrade(beacon, instance, code);
    }

    _upgrades[_nextProposalID] = Upgrade(beacon, instance, code);
    // Doesn't index code as parsing the Beacon's logs for its indexed code argument
    // will return every time a contract upgraded to it
    // This combination of options should be competent for almost all use cases
    // The only missing indexing case is when it's proposed to upgrade, yet that never passes/executes
    // This should be minimally considerable and coverable by outside solutions if truly needed
    emit UpgradeProposed(_nextProposalID, beacon, instance, code);
    return _createProposal(uint256(CommonProposalType.Upgrade) | commonProposalBit, info);
  }

  function proposeTokenAction(
    address token,
    address target,
    // Redundant field for Threads which don't (at least currently) have minting
    bool mint,
    uint256 price,
    uint256 amount,
    string calldata info
  ) external returns (uint256) {
    if (mint) {
      if (token != erc20) {
        revert MintingDifferentToken(token, erc20);
      }
      if (!IFrabricERC20(erc20).mintable()) {
        revert NotMintable();
      }
    }

    if (price != 0) {
      // Target is ignored when selling tokens, yet not when minting them
      // This enables minting and directly selling tokens, and removes mutability reducing scope
      if (target != address(this)) {
        revert SellingWithDifferentTarget(target, address(this));
      }

      // Ensure that we know how to sell this token
      if (!token.supportsInterface(type(IIntegratedLimitOrderDEX).interfaceId)) {
        revert UnsupportedInterface(token, type(IIntegratedLimitOrderDEX).interfaceId);
      }

      // Because this is an ILO DEX, amount here will be atomic yet the ILO DEX
      // will expect it to be whole
      if ((amount / 1e18 * 1e18) != amount) {
        revert NotRoundAmount(amount);
      }
    }

    _tokenActions[_nextProposalID] = TokenAction(token, target, mint, price, amount);
    emit TokenActionProposed(_nextProposalID, token, target, mint, price, amount);
    return _createProposal(uint256(CommonProposalType.TokenAction) | commonProposalBit, info);
  }

  function proposeParticipantRemoval(
    address participant,
    string calldata info
  ) external returns (uint256) {
    _removals[_nextProposalID] = participant;
    emit RemovalProposed(_nextProposalID, participant);
    return _createProposal(uint256(CommonProposalType.ParticipantRemoval) | commonProposalBit, info);
  }

  // Has an empty body as it doesn't have to be overriden
  function _participantRemoval(address participant) internal virtual {}
  // Has to be overriden
  function _completeSpecificProposal(uint256, uint256) internal virtual;

  // Re-entrancy isn't a concern due to completeProposal being safe from re-entrancy
  // That's the only thing which should call this
  function _completeProposal(uint256 id, uint256 _pType) internal override {
    if ((_pType & commonProposalBit) == commonProposalBit) {
      CommonProposalType pType = CommonProposalType(_pType ^ commonProposalBit);
      if (pType == CommonProposalType.Paper) {
        // NOP as the DAO emits ProposalStateChanged which is all that's needed for this

      } else if (pType == CommonProposalType.Upgrade) {
        Upgrade storage upgrade = _upgrades[id];
        IFrabricBeacon(upgrade.beacon).upgrade(upgrade.instance, upgrade.code);
        delete _upgrades[id];

      } else if (pType == CommonProposalType.TokenAction) {
        TokenAction storage action = _tokenActions[id];
        if (action.mint) {
          IFrabricERC20(erc20).mint(action.target, action.amount);
        // The ILO DEX doesn't require transfer or even approve
        } else if (action.price == 0) {
          IERC20(action.token).safeTransfer(action.target, action.amount);
        }

        // Not else to allow direct mint + sell
        if (action.price != 0) {
          IIntegratedLimitOrderDEX(action.token).sell(action.price, action.amount / 1e18);
        }
        delete _tokenActions[id];

      } else if (pType == CommonProposalType.ParticipantRemoval) {
        address removed = _removals[id];
        IFrabricERC20(erc20).setWhitelisted(removed, bytes32(0));
        _participantRemoval(removed);
        delete _removals[id];

      } else {
        revert UnhandledEnumCase("FrabricDAO _completeProposal CommonProposal", _pType);
      }

    } else {
      _completeSpecificProposal(id, _pType);
    }
  }
}
