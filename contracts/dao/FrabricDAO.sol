// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.9;

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/erc20/IIntegratedLimitOrderDEX.sol";
import "../interfaces/proxy/IBeaconProxied.sol";
import "../interfaces/proxy/IBeacon.sol";

import "./DAO.sol";

import "../interfaces/dao/IFrabricDAO.sol";

// Implements proposals mutual to both Threads and the Frabric
abstract contract FrabricDAO is IFrabricDAO, DAO {
  using SafeERC20 for IERC20;

  uint256 constant public commonProposalBit = 1 << 255;

  enum CommonProposalType {
    Paper,
    Upgrade,
    TokenAction
  }

  struct Upgrade {
    address instance;
    address code;
  }
  mapping(uint256 => Upgrade) internal _upgrade;

  struct TokenAction {
    address token;
    address target;
    bool mint;
    uint256 price;
    uint256 amount;
  }
  mapping(uint256 => TokenAction) internal _tokenAction;

  // Don't allow anyone to propose. This function should always be overriden
  function canPropose() public virtual view returns (bool) {
    return false;
  }

  modifier beforeProposal() {
    require(canPropose(), "FrabricDAO: Proposal requirements not met");
    _;
  }

  function proposePaper(string calldata info) external beforeProposal() returns (uint256) {
    // No dedicated event as the DAO emits type and info
    return _createProposal(info, uint256(CommonProposalType.Paper) | commonProposalBit);
  }

  // Allows upgrading itself or any contract owned by itself
  function proposeUpgrade(
    string calldata info,
    address instance,
    address code
  ) external beforeProposal() returns (uint256) {
    _upgrade[_nextProposalID] = Upgrade(instance, code);
    emit UpgradeProposed(_nextProposalID, instance, code);
    return _createProposal(info, uint256(CommonProposalType.Upgrade) | commonProposalBit);
  }

  function proposeTokenAction(
    string calldata info,
    address token,
    address target,
    // Redundant field for Threads which don't (at least currently) have minting
    bool mint,
    uint256 price,
    uint256 amount
  ) external beforeProposal() returns (uint256) {
    if (mint) {
      require(token == erc20, "FrabricDAO: Proposing minting a different token");
      require(IFrabricERC20(erc20).mintable(), "FrabricDAO: Token isn't mintable");
    }

    if (price != 0) {
      // Target is ignored when selling tokens, yet not when minting them
      // This enables minting and directly selling tokens, and removes mutability reducing scope
      require(target == address(this), "FrabricDAO: Token sales must set self as the target");
    }

    _tokenAction[_nextProposalID] = TokenAction(token, target, mint, price, amount);
    emit TokenActionProposed(_nextProposalID, token, target, mint, price, amount);
    return _createProposal(info, uint256(CommonProposalType.TokenAction) | commonProposalBit);
  }

  function _completeSpecificProposal(uint256, uint256) internal virtual {
    require(false, "FrabricDAO: _completeSpecificProposal wasn't implemented");
  }

  // Re-entrancy isn't a concern due to completeProposal being safe from re-entrancy
  // That's the only thing which should call this
  function _completeProposal(uint256 id, uint256 _proposalType) internal override {
    if ((_proposalType & commonProposalBit) == commonProposalBit) {
      CommonProposalType proposalType = CommonProposalType(_proposalType ^ commonProposalBit);
      if (proposalType == CommonProposalType.Paper) {
        // NOP as the DAO emits ProposalStateChanged

      } else if (proposalType == CommonProposalType.Upgrade) {
        IBeacon(IBeaconProxied(_upgrade[id].instance).beacon()).upgrade(_upgrade[id].instance, _upgrade[id].code);
        delete _upgrade[id];

      } else if (proposalType == CommonProposalType.TokenAction) {
        if (_tokenAction[id].mint) {
          IFrabricERC20(erc20).mint(_tokenAction[id].target, _tokenAction[id].amount);
        // The ILO DEX doesn't require transfer or even approve
        } else if (_tokenAction[id].price == 0) {
          IERC20(_tokenAction[id].token).safeTransfer(_tokenAction[id].target, _tokenAction[id].amount);
        }

        // Not else to allow direct mint + sell
        if (_tokenAction[id].price != 0) {
          IIntegratedLimitOrderDEX(_tokenAction[id].token).sell(_tokenAction[id].price, _tokenAction[id].amount);
        }
        delete _tokenAction[id];

      } else {
        require(false, "FrabricDAO: Completing unknown proposal type");
      }
    } else {
      _completeSpecificProposal(id, _proposalType);
    }
  }
}
