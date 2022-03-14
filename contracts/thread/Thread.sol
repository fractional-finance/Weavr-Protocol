// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../interfaces/erc20/IFrabricERC20.sol";
import "../interfaces/thread/ICrowdfund.sol";
import "../interfaces/thread/IThread.sol";

import "../dao/DAO.sol";

contract Thread is IThread, Initializable, DAO {
  using SafeERC20 for IERC20;

  address public override crowdfund;
  address public override agent;
  address public override frabric;

  struct Dissolution {
    address purchaser;
    address token;
    uint256 amount;
  }

  // Private as all this info is available via events
  mapping(uint256 => address) private _agents;
  mapping(uint256 => address) private _frabrics;
  mapping(uint256 => Dissolution) private _dissolutions;

  // Normalize the Crowdfund token amount to the Thread's
  function normalize(uint256 amount) internal view returns (uint256) {
    return amount * (10 ** (18 - IERC20Metadata(crowdfund).decimals()));
  }

  function initialize(
    address _crowdfund,
    address _erc20,
    string memory name,
    string memory symbol,
    address parentWhitelist,
    address _agent,
    address raiseToken,
    uint256 target
  ) public initializer {
    // The Frabric uses a 2 week voting period. If it wants to upgrade every Thread on the Frabric's code,
    // then it will be able to push an update in 2 weeks. If a Thread sees the new code and wants out,
    // it needs a shorter window in order to explicitly upgrade to the existing code to prevent Frabric upgrades
    __DAO_init(_erc20, 1 weeks);
    crowdfund = _crowdfund;
    ICrowdfund(crowdfund).initialize(name, symbol, parentWhitelist, _agent, address(this), raiseToken, target);
    IFrabricERC20(erc20).initialize(name, symbol, normalize(target), false, parentWhitelist);
    agent = _agent;
    emit AgentChanged(address(0), agent);
  }

  // Initialize with null info to prevent anyone from accessing this contract
  constructor() {
    initialize(address(0), address(0), "", "", address(0), address(0), address(0), 0);
  }

  function migrateFromCrowdfund() external {
    uint256 balance = IERC20(crowdfund).balanceOf(msg.sender);
    ICrowdfund(crowdfund).burn(msg.sender, balance);
    IERC20(erc20).transfer(msg.sender, normalize(balance));
  }

  modifier beforeProposal() {
    require(
      (IERC20(erc20).balanceOf(msg.sender) != 0) ||
      (msg.sender == address(agent)) ||
      (msg.sender == address(frabric)),
      "Thread: Proposer is not authorized to create a proposal"
    );
    _;
  }

  function proposePaper(string calldata info) external beforeProposal() override returns (uint256) {
    emit PaperProposed(_nextProposalID, info);
    return _createProposal(info, 0);
  }

  function proposeAgentChange(
    string calldata info,
    address _agent
  ) external beforeProposal() override returns (uint256 id) {
    _agents[_nextProposalID] = _agent;
    emit AgentChangeProposed(_nextProposalID, _agent);
    return _createProposal(info, 1);
  }

  function proposeFrabricChange(
    string calldata info,
    address _frabric
  ) external beforeProposal() override returns (uint256 id) {
    _frabrics[_nextProposalID] = _frabric;
    emit FrabricChangeProposed(_nextProposalID, _frabric);
    return _createProposal(info, 2);
  }

  function proposeDissolution(
    string calldata info,
    address purchaser,
    address token,
    uint256 amount
  ) external beforeProposal() override returns (uint256 id) {
    require(amount != 0, "Thread: Dissolution amount is 0");
    _dissolutions[_nextProposalID] = Dissolution(purchaser, token, amount);
    emit DissolutionProposed(_nextProposalID, purchaser, token, amount);
    return _createProposal(info, 3);
  }

  function _completeProposal(uint256 id, uint256 proposalType) internal override {
    if (proposalType == 0) {
      // Agent should view the Proposal's info
      emit PaperDecision(id);
    } else if (proposalType == 1) {
      emit AgentChanged(agent, _agents[id]);
      agent = _agents[id];
    } else if (proposalType == 2) {
      emit FrabricChanged(frabric, _frabrics[id]);
      frabric = _frabrics[id];
    } else if (proposalType == 3) {
      Dissolution memory dissolution = _dissolutions[id];
      IERC20(dissolution.token).safeTransferFrom(dissolution.purchaser, address(this), dissolution.amount);
      IFrabricERC20(erc20).pause();
      IERC20(dissolution.token).approve(erc20, dissolution.amount);
      IFrabricERC20(erc20).distribute(dissolution.token, dissolution.amount);
      emit Dissolved(id);
    } else {
      require(false, "Thread: Proposal type doesn't exist");
    }
  }
}
