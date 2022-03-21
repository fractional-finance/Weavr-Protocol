// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/erc20/IDividendERC20.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/thread/IThread.sol";

contract Thread is Initializable, FrabricDAO, IThread {
  using SafeERC20 for IERC20;

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

  function initialize(
    address _erc20,
    address _agent,
    address _frabric
  ) external initializer {
    // The Frabric uses a 2 week voting period. If it wants to upgrade every Thread on the Frabric's code,
    // then it will be able to push an update in 2 weeks. If a Thread sees the new code and wants out,
    // it needs a shorter window in order to explicitly upgrade to the existing code to prevent Frabric upgrades
    __FrabricDAO_init(_erc20, 1 weeks);
    agent = _agent;
    frabric = _frabric;
    emit AgentChanged(address(0), agent);
    emit FrabricChanged(address(0), frabric);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function canPropose() public view override(IFrabricDAO, FrabricDAO) returns (bool) {
    return (
      (IERC20(erc20).balanceOf(msg.sender) != 0) ||
      (msg.sender == address(agent)) ||
      (msg.sender == address(frabric))
    );
  }

  function proposeAgentChange(
    address _agent,
    string calldata info
  ) external beforeProposal() override returns (uint256 id) {
    _agents[_nextProposalID] = _agent;
    emit AgentChangeProposed(_nextProposalID, _agent);
    return _createProposal(info, uint256(ThreadProposalType.AgentChange));
  }

  function proposeFrabricChange(
    address _frabric,
    string calldata info
  ) external beforeProposal() override returns (uint256 id) {
    _frabrics[_nextProposalID] = _frabric;
    emit FrabricChangeProposed(_nextProposalID, _frabric);
    return _createProposal(info, uint256(ThreadProposalType.FrabricChange));
  }

  function proposeDissolution(
    address token,
    uint256 amount,
    string calldata info
  ) external beforeProposal() override returns (uint256 id) {
    require(amount != 0, "Thread: Dissolution amount is 0");
    _dissolutions[_nextProposalID] = Dissolution(msg.sender, token, amount);
    emit DissolutionProposed(_nextProposalID, msg.sender, token, amount);
    return _createProposal(info, uint256(ThreadProposalType.Dissolution));
  }

  function _completeSpecificProposal(uint256 id, uint256 _proposalType) internal override {
    ThreadProposalType pType = ThreadProposalType(_proposalType);
    if (pType == ThreadProposalType.AgentChange) {
      emit AgentChanged(agent, _agents[id]);
      agent = _agents[id];
    } else if (pType == ThreadProposalType.FrabricChange) {
      emit FrabricChanged(frabric, _frabrics[id]);
      frabric = _frabrics[id];
    } else if (pType == ThreadProposalType.Dissolution) {
      // Prevent the Thread from being locked up in a Dissolution the agent won't honor for whatever reason
      // This will issue payment and then the agent will be obligated to transfer property or have bond slashed
      // Not calling complete on a passed Dissolution may also be grounds for a bond slash
      // The intent is to allow the agent to not listen to impropriety with the Frabric as arbitrator
      // See the Frabric's community policies for more information on process
      require(msg.sender == agent, "Thread: Only the agent can complete a dissolution proposal");
      Dissolution memory dissolution = _dissolutions[id];
      IERC20(dissolution.token).safeTransferFrom(dissolution.purchaser, address(this), dissolution.amount);
      IFrabricERC20(erc20).pause();
      IERC20(dissolution.token).approve(erc20, dissolution.amount);
      // See IFrabricERC20 for why that doesn't include IDividendERC20 despite FrabricERC20 being a DividendERC20
      IDividendERC20(erc20).distribute(dissolution.token, dissolution.amount);
      emit Dissolved(id);
    } else {
      require(false, "Thread: Trying to complete an unknown proposal type");
    }
  }
}
