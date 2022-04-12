// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/erc20/IDistributionERC20.sol";
import "../interfaces/erc20/IFrabricERC20.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IBond.sol";
import "../interfaces/frabric/IFrabric.sol";
import "../interfaces/thread/IThread.sol";

contract Thread is FrabricDAO, IThreadInitializable {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  uint256 public override upgradesEnabled;

  bytes32 public override descriptor;

  address public override agent;
  address public override frabric;

  struct Dissolution {
    address purchaser;
    address token;
    uint256 price;
  }

  // Private as all this info is available via events
  mapping(uint256 => bytes32) private _descriptors;
  mapping(uint256 => address) private _agents;
  mapping(uint256 => address) private _frabrics;
  mapping(uint256 => Dissolution) private _dissolutions;

  modifier viableFrabric(address _frabric) {
    // Technically not needed, healthy to have
    if (IComposable(_frabric).contractName() != keccak256("Frabric")) {
      revert DifferentContract(IComposable(_frabric).contractName(), keccak256("Frabric"));
    }

    // Technically, the erc20 of this DAO must implement FrabricWhitelist
    // That is implied by this Frabric implementing IDAO and when this executes,
    // setParentWhitelist is executed, confirming the FrabricWhitelist interface
    // is supported by it
    if (!_frabric.supportsInterface(type(IDAOCore).interfaceId)) {
      revert UnsupportedInterface(_frabric, type(IDAOCore).interfaceId);
    }

    if (!_frabric.supportsInterface(type(IFrabricCore).interfaceId)) {
      revert UnsupportedInterface(_frabric, type(IFrabricCore).interfaceId);
    }

    _;
  }

  function _setFrabric(address _frabric) private viableFrabric(_frabric) {
    emit FrabricChanged(frabric, _frabric);
    frabric = _frabric;
    // Update the parent whitelist as well, if we're not still initializing
    if (IFrabricWhitelist(erc20).parentWhitelist() != address(0)) {
      IFrabricERC20(erc20).setParentWhitelist(IDAO(frabric).erc20());
    }
  }

  modifier viableAgent(address _agent) {
    if (IFrabricCore(frabric).governor(_agent) != IFrabricCore.GovernorStatus.Active) {
      revert NotActiveGovernor(_agent, IFrabricCore(frabric).governor(_agent));
    }

    _;
  }

  function _setAgent(address _agent) private viableAgent(_agent) {
    emit AgentChanged(agent, _agent);
    agent = _agent;
  }

  function initialize(
    string calldata name,
    address _erc20,
    bytes32 _descriptor,
    address _frabric,
    address _agent
  ) external override initializer {
    // The Frabric uses a 2 week voting period. If it wants to upgrade every Thread on the Frabric's code,
    // then it will be able to push an update in 2 weeks. If a Thread sees the new code and wants out,
    // it needs a shorter window in order to explicitly upgrade to the existing code to prevent Frabric upgrades
    __FrabricDAO_init(
      string(abi.encodePacked("Thread: ", name)),
      _erc20,
      1 weeks
    );

    __Composable_init("Thread", false);
    supportsInterface[type(IThread).interfaceId] = true;

    descriptor = _descriptor;
    _setFrabric(_frabric);
    _setAgent(_agent);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Thread") initializer {}

  // Allows proposing even when paused so TokenActions can be issued to recover funds
  // from this DAO. Also theoretically enables proposing an Upgrade to undo the pause
  // if that's desired for whatever reason
  function canPropose() public view override(DAO, IDAOCore) returns (bool) {
    return (
      // Whitelisted token holder
      (
        IWhitelist(erc20).whitelisted(msg.sender) &&
        (IERC20(erc20).balanceOf(msg.sender) != 0)
      ) ||
      // Both of these should also be whitelisted. It's not technically a requirement however
      // The Thread is allowed to specify whoever they want for either, and if they are splitting off,
      // they should successfully manage their own whitelist, yet there's no reason to force it here
      // Agent
      (msg.sender == address(agent)) ||
      // Frabric
      (msg.sender == address(frabric))
    );
  }

  function _canProposeUpgrade(
    address beacon,
    address instance,
    address impl
  ) internal view override returns (bool) {
    return (
      // If upgrades are enabled, all good
      (block.timestamp >= upgradesEnabled) ||
      // Upgrades to the current impl/release channels are always allowed
      // This prevents the Frabric from forcing an update onto Threads and allows
      // switching between versions presumably published by the Frabric
      (impl == IFrabricBeacon(beacon).implementation(instance)) ||
      (uint160(impl) <= IFrabricBeacon(beacon).releaseChannels())
    );
  }

  function proposeEnablingUpgrades(bytes32 info) external returns (uint256) {
    // Doesn't emit a dedicated event for the same reason Paper proposals don't
    return _createProposal(uint16(ThreadProposalType.EnableUpgrades), info);
  }

  function proposeDescriptorChange(
    bytes32 _descriptor,
    bytes32 info
  ) external override returns (uint256) {
    _descriptors[_nextProposalID] = _descriptor;
    emit DescriptorChangeProposed(_nextProposalID, _descriptor);
    return _createProposal(uint16(ThreadProposalType.DescriptorChange), info);
  }

  function proposeAgentChange(
    address _agent,
    bytes32 info
  ) external override viableAgent(_agent) returns (uint256) {
    // We could validate this agent is a valid governor at this time yet it's
    // the Thread's choice to make
    _agents[_nextProposalID] = _agent;
    emit AgentChangeProposed(_nextProposalID, _agent);
    return _createProposal(uint16(ThreadProposalType.AgentChange), info);
  }

  function proposeFrabricChange(
    address _frabric,
    bytes32 info
  ) external override viableFrabric(_frabric) returns (uint256) {
    _frabrics[_nextProposalID] = _frabric;
    emit FrabricChangeProposed(_nextProposalID, _frabric);
    return _createProposal(uint16(ThreadProposalType.FrabricChange), info);
  }

  function proposeDissolution(
    address token,
    uint256 price,
    bytes32 info
  ) external override returns (uint256) {
    if (price == 0) {
      revert ZeroPrice();
    }
    _dissolutions[_nextProposalID] = Dissolution(msg.sender, token, price);
    emit DissolutionProposed(_nextProposalID, msg.sender, token, price);
    return _createProposal(uint16(ThreadProposalType.Dissolution), info);
  }

  function _completeSpecificProposal(uint256 id, uint256 _pType) internal override {
    ThreadProposalType pType = ThreadProposalType(_pType);
    if (pType == ThreadProposalType.EnableUpgrades) {
      // Enable upgrades after the Frabric's voting period + 1 week

      // There is an attack where a Thread upgrades and claws back timelocked tokens
      // Once this proposal passes, the Frabric can immediately void its timelock,
      // yet it'll need 2 weeks to pass a proposal on what to do with them
      // The added 1 week is because neither selling on the token's DEX nor an auction
      // would complete instantly, so this gives a buffer for it to execute

      // While the Frabric also needs time to decide what to do and can't be expected
      // to be perfect with time, enabling upgrades only enables Upgrade proposals to be created
      // That means there's an additional delay of the Thread's voting period (1 week)
      // while the actual Upgrade proposal occurs, granting that time
      upgradesEnabled = block.timestamp + IDAOCore(frabric).votingPeriod() + (1 weeks);

    } else if (pType == ThreadProposalType.DescriptorChange) {
      emit DescriptorChanged(descriptor, _descriptors[id]);
      descriptor = _descriptors[id];
      delete _descriptors[id];

    } else if (pType == ThreadProposalType.AgentChange) {
      emit AgentChanged(agent, _agents[id]);
      agent = _agents[id];
      delete _agents[id];

      // Have the agent themselves complete this proposal to signify their consent
      // to becoming the agent for this Thread
      if (msg.sender != agent) {
        revert NotAgent(msg.sender, agent);
      }

    } else if (pType == ThreadProposalType.FrabricChange) {
      emit FrabricChanged(frabric, _frabrics[id]);
      frabric = _frabrics[id];
      delete _frabrics[id];
      // Update our parent whitelist to the new Frabric's
      IFrabricERC20(erc20).setParentWhitelist(IDAOCore(frabric).erc20());

    } else if (pType == ThreadProposalType.Dissolution) {
      // Prevent the Thread from being locked up in a Dissolution the agent won't honor for whatever reason
      // This will issue payment and then the agent will be obligated to transfer property or have bond slashed
      // Not calling complete on a passed Dissolution may also be grounds for a bond slash
      // The intent is to allow the agent to not listen to impropriety with the Frabric as arbitrator
      // See the Frabric's community policies for more information on process
      if (msg.sender != agent) {
        revert NotAgent(msg.sender, agent);
      }
      Dissolution storage dissolution = _dissolutions[id];
      IERC20(dissolution.token).safeTransferFrom(dissolution.purchaser, address(this), dissolution.price);
      IFrabricERC20(erc20).pause();
      IERC20(dissolution.token).safeIncreaseAllowance(erc20, dissolution.price);
      IFrabricERC20(erc20).distribute(dissolution.token, dissolution.price);
      emit Dissolved(id);
      delete _dissolutions[id];

    } else {
      revert UnhandledEnumCase("Thread _completeSpecificProposal", _pType);
    }
  }
}
