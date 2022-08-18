// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { StorageSlotUpgradeable as StorageSlot } from "@openzeppelin/contracts-upgradeable/utils/StorageSlotUpgradeable.sol";

import "../interfaces/frabric/IBond.sol";
import "../interfaces/thread/IThreadDeployer.sol";
import "../interfaces/thread/IThread.sol";

import "../dao/FrabricDAO.sol";

import "../interfaces/frabric/IInitialFrabric.sol";
import "../interfaces/frabric/IFrabric.sol";

contract Frabric is FrabricDAO, IFrabricUpgradeable {
  using ERC165Checker for address;

  mapping(address => ParticipantType) public override participant;
  mapping(address => GovernorStatus) public override governor;

  address public override bond;
  address public override threadDeployer;

  struct Participant {
    ParticipantType pType;
    address addr;
  }
  // The proposal structs are private as their events are easily grabbed and contain the needed information
  mapping(uint256 => Participant) private _participants;

  struct BondRemoval {
    address governor;
    bool slash;
    uint256 amount;
  }
  mapping(uint256 => BondRemoval) private _bondRemovals;

  struct Thread {
    uint8 variant;
    address governor;
    // This may not actually pack yet it's small enough to theoretically
    string symbol;
    bytes32 descriptor;
    string name;
    bytes data;
  }
  mapping(uint256 => Thread) private _threads;

  struct ThreadProposalStruct {
    address thread;
    bytes4 selector;
    bytes data;
  }
  mapping(uint256 => ThreadProposalStruct) private _threadProposals;

  mapping(address => uint256) public override vouchers;

  mapping(uint16 => bytes4) private _proposalSelectors;

  function validateUpgrade(uint256 _version, bytes calldata data) external view override {
    if (_version != 2) {
      revert InvalidVersion(_version, 2);
    }

    (address _bond, address _threadDeployer, ) = abi.decode(data, (address, address, address));
    if (!_bond.supportsInterface(type(IBondCore).interfaceId)) {
      revert errors.UnsupportedInterface(_bond, type(IBondCore).interfaceId);
    }
    if (!_threadDeployer.supportsInterface(type(IThreadDeployer).interfaceId)) {
      revert errors.UnsupportedInterface(_threadDeployer, type(IThreadDeployer).interfaceId);
    }
  }

  function _changeParticipant(address _participant, ParticipantType pType) private {
    participant[_participant] = pType;
    emit ParticipantChange(pType, _participant);
  }

  function _changeParticipantAndKYC(address _participant, ParticipantType pType, bytes32 kycHash) private {
    _changeParticipant(_participant, pType);
    IFrabricWhitelistCore(erc20).setKYC(_participant, kycHash, 0);
  }

  function _whitelistAndAdd(address _participant, ParticipantType pType, bytes32 kycHash) private {
    IFrabricWhitelistCore(erc20).whitelist(_participant);
    _changeParticipantAndKYC(_participant, pType, kycHash);
  }

  function _addKYC(address kyc) private {
    _whitelistAndAdd(kyc, ParticipantType.KYC, keccak256(abi.encodePacked("KYC ", kyc)));
  }

  function upgrade(uint256 _version, bytes calldata data) external override {
    address beacon = StorageSlot.getAddressSlot(
      // Beacon storage slot
      0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50
    ).value;
    if (msg.sender != beacon) {
      revert NotBeacon(msg.sender, beacon);
    }

    // While this isn't possible for this version (2), it is possible if this was
    // code version 3 yet triggerUpgrade was never called for version 2
    // In that scenario, this could be called with version 2 data despite expecting
    // version 3 data
    if (_version != (version + 1)) {
      revert InvalidVersion(_version, version + 1);
    }
    version++;

    // Drop support for IInitialFrabric
    // While we do still match it, and it shouldn't hurt to keep it around,
    // we never want to encourage its usage, nor do we want to forget about it
    // if we ever do introduce an incompatibility
    supportsInterface[type(IInitialFrabric).interfaceId] = false;

    // Add support for the new Frabric interfaces
    supportsInterface[type(IFrabricCore).interfaceId] = true;
    supportsInterface[type(IFrabric).interfaceId] = true;

    // Set bond, threadDeployer, and an initial KYC/governor
    address kyc;
    address _governor;
    (bond, threadDeployer, kyc, _governor) = abi.decode(data, (address, address, address, address));

    _addKYC(kyc);

    _whitelistAndAdd(_governor, ParticipantType.Governor, keccak256("Initial Governor"));
    governor[_governor] = GovernorStatus.Active;

    _proposalSelectors[uint16(CommonProposalType.Paper)       ^ commonProposalBit] = IFrabricDAO.proposePaper.selector;
    _proposalSelectors[uint16(CommonProposalType.Upgrade)     ^ commonProposalBit] = IFrabricDAO.proposeUpgrade.selector;
    _proposalSelectors[uint16(CommonProposalType.TokenAction) ^ commonProposalBit] = IFrabricDAO.proposeTokenAction.selector;

    _proposalSelectors[uint16(IThread.ThreadProposalType.DescriptorChange)] = IThread.proposeDescriptorChange.selector;
    _proposalSelectors[uint16(IThread.ThreadProposalType.GovernorChange)]   = IThread.proposeGovernorChange.selector;
    _proposalSelectors[uint16(IThread.ThreadProposalType.Dissolution)]      = IThread.proposeDissolution.selector;

    // Correct the voting time as well
    votingPeriod = 1 weeks;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Frabric") initializer {
    // Only set in the constructor as this has no value being in the live contract
    supportsInterface[type(IUpgradeable).interfaceId] = true;
  }

  function canPropose(address proposer) public view override(DAO, IDAOCore) returns (bool) {
    return uint8(participant[proposer]) >= uint8(ParticipantType.Genesis);
  }

  function proposeParticipant(
    ParticipantType participantType,
    address _participant,
    bytes32 info
  ) external override returns (uint256 id) {
    if (
      (participantType < ParticipantType.KYC) ||
      (ParticipantType.Voucher < participantType)
    ) {
      revert InvalidParticipantType(participantType);
    }

    if (
      (participant[_participant] != ParticipantType.Null) ||
      IFrabricWhitelistCore(erc20).whitelisted(_participant)
    ) {
      revert ParticipantAlreadyApproved(_participant);
    }

    id = _createProposal(uint16(FrabricProposalType.Participant), false, info);
    _participants[id] = Participant(participantType, _participant);
    emit ParticipantProposal(id, participantType, msg.sender, _participant);
  }

  function proposeBondRemoval(
    address _governor,
    bool slash,
    uint256 amount,
    bytes32 info
  ) external override returns (uint256 id) {
    id = _createProposal(uint16(FrabricProposalType.RemoveBond), false, info);
    _bondRemovals[id] = BondRemoval(_governor, slash, amount);
    if (governor[_governor] < GovernorStatus.Active) {
      // Arguably a misuse as this actually checks they were never an active governor
      // Not that they aren't currently an active governor, which the error name suggests
      // This should be better to handle from an integration perspective however
      revert NotActiveGovernor(_governor, governor[_governor]);
    }
    emit BondRemovalProposal(id, _governor, slash, amount);
  }

  function proposeThread(
    uint8 variant,
    string calldata name,
    string calldata symbol,
    bytes32 descriptor,
    bytes calldata data,
    bytes32 info
  ) external override returns (uint256 id) {
    if (version < 2) {
      revert NotUpgraded(version, 2);
    }

    if (governor[msg.sender] != GovernorStatus.Active) {
      revert NotActiveGovernor(msg.sender, governor[msg.sender]);
    }

    // Doesn't check for being alphanumeric due to iteration costs
    if (
      (bytes(name).length < 6) || (bytes(name).length > 64) ||
      (bytes(symbol).length < 2) || (bytes(symbol).length > 5)
    ) {
      revert InvalidName(name, symbol);
    }
    // Validate the data now before creating the proposal
    // ThreadProposal doesn't have this same level of validation yet not only are
    // Threads a far more integral part of the system, ThreadProposal deals with an enum
    // for proposal type. This variant field is a uint256 which has a much larger impact scope
    IThreadDeployer(threadDeployer).validate(variant, data);

    id = _createProposal(uint16(FrabricProposalType.Thread), false, info);
    Thread storage proposal = _threads[id];
    proposal.variant = variant;
    proposal.name = name;
    proposal.symbol = symbol;
    proposal.descriptor = descriptor;
    proposal.governor = msg.sender;
    proposal.data = data;
    emit ThreadProposal(id, variant, msg.sender, name, symbol, descriptor, data);
  }

  // This does assume the Thread's API meets expectations compiled into the Frabric
  // They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  // These are both valid behaviors intended to be accessible by Threads
  function proposeThreadProposal(
    address thread,
    uint16 _proposalType,
    bytes calldata data,
    bytes32 info
  ) external returns (uint256 id) {
    // Technically not needed given we check for interface support, yet a healthy check to have
    if (IComposable(thread).contractName() != keccak256("Thread")) {
      revert DifferentContract(IComposable(thread).contractName(), keccak256("Thread"));
    }

    // Lock down the selector to prevent arbitrary calls
    // While data is still arbitrary, it has reduced scope thanks to this, and can only be decoded in expected ways
    // data isn't validated to be technically correct as the UI is trusted to sanity check it
    // and present it accurately for humans to deliberate on
    bytes4 selector;
    if (_isCommonProposal(_proposalType)) {
      if (!thread.supportsInterface(type(IFrabricDAO).interfaceId)) {
        revert errors.UnsupportedInterface(thread, type(IFrabricDAO).interfaceId);
      }
    } else {
      if (!thread.supportsInterface(type(IThread).interfaceId)) {
        revert errors.UnsupportedInterface(thread, type(IThread).interfaceId);
      }
    }
    selector = _proposalSelectors[_proposalType];
    if (selector == bytes4(0)) {
      revert errors.UnhandledEnumCase("Frabric proposeThreadProposal", _proposalType);
    }

    id = _createProposal(uint16(FrabricProposalType.ThreadProposal), false, info);
    _threadProposals[id] = ThreadProposalStruct(thread, selector, data);
    emit ThreadProposalProposal(id, thread, _proposalType, data);
  }

  function _participantRemoval(address _participant) internal override {
    if (governor[_participant] != GovernorStatus.Null) {
      governor[_participant] = GovernorStatus.Removed;
    }
    _changeParticipant(_participant, ParticipantType.Removed);
  }

  function _completeSpecificProposal(uint256 id, uint256 _pType) internal override {
    FrabricProposalType pType = FrabricProposalType(_pType);
    if (pType == FrabricProposalType.Participant) {
      Participant storage _participant = _participants[id];
      // This check also exists in proposeParticipant, yet that doesn't prevent
      // the same participant from being proposed multiple times simultaneously
      // This is an edge case which should never happen, yet handling it means
      // checking here to ensure if they already exist, they're not overwritten
      // While we could error here, we may as well delete the invalid proposal and move on with life
      if (participant[_participant.addr] != ParticipantType.Null) {
        delete _participants[id];
        return;
      }

      if (_participant.pType == ParticipantType.KYC) {
        _addKYC(_participant.addr);
        delete _participants[id];
      } else {
        // Whitelist them until they're KYCd
        IFrabricWhitelistCore(erc20).whitelist(_participant.addr);
      }

    } else if (pType == FrabricProposalType.RemoveBond) {
      if (version < 2) {
        revert NotUpgraded(version, 2);
      }

      BondRemoval storage remove = _bondRemovals[id];
      if (remove.slash) {
        IBondCore(bond).slash(remove.governor, remove.amount);
      } else {
        IBondCore(bond).unbond(remove.governor, remove.amount);
      }
      delete _bondRemovals[id];

    } else if (pType == FrabricProposalType.Thread) {
      Thread storage proposal = _threads[id];
      // This governor may no longer be viable for usage yet the Thread will check
      // When proposing this proposal type, we validate we upgraded which means this has been set
      IThreadDeployer(threadDeployer).deploy(
        proposal.variant, proposal.name, proposal.symbol, proposal.descriptor, proposal.governor, proposal.data
      );
      delete _threads[id];

    } else if (pType == FrabricProposalType.ThreadProposal) {
      ThreadProposalStruct storage proposal = _threadProposals[id];
      (bool success, bytes memory data) = proposal.thread.call(
        abi.encodePacked(proposal.selector, proposal.data)
      );
      if (!success) {
        revert errors.ExternalCallFailed(proposal.thread, proposal.selector, data);
      }
      delete _threadProposals[id];
    } else {
      revert errors.UnhandledEnumCase("Frabric _completeSpecificProposal", _pType);
    }
  }

  function vouch(address _participant, bytes calldata signature) external override {
    // Places signer in a variable to make the information available for the error
    // While generally, the errors include an abundance of information with the expectation they'll be caught in a call,
    // and even if they are executed on chain, we don't care about the increased gas costs for the extreme minority,
    // this calculation is extensive enough it's worth the variable (which shouldn't even change gas costs?)
    address signer = ECDSA.recover(
      _hashTypedDataV4(
        keccak256(
          abi.encode(keccak256("Vouch(address participant)"), _participant)
        )
      ),
      signature
    );

    if (!IFrabricWhitelistCore(erc20).hasKYC(signer)) {
      revert NotKYC(signer);
    }

    if (participant[signer] != ParticipantType.Voucher) {
      // Declared optimal growth number
      if (vouchers[signer] == 6) {
        revert OutOfVouchers(signer);
      }
      vouchers[signer] += 1;
    }

    // The fact whitelist can only be called once for a given participant makes this secure against replay attacks
    IFrabricWhitelistCore(erc20).whitelist(_participant);
    emit Vouch(signer, _participant);
  }

  function approve(
    ParticipantType pType,
    address approving,
    bytes32 kycHash,
    bytes calldata signature
  ) external override {
    if ((pType == ParticipantType.Null) && passed[uint160(approving)]) {
      address temp = _participants[uint160(approving)].addr;
      if (temp == address(0)) {
        // While approving is actually a proposal ID, it's the most info we have
        revert ParticipantAlreadyApproved(approving);
      }
      pType = _participants[uint160(approving)].pType;
      delete _participants[uint160(approving)];
      approving = temp;
    } else if ((pType != ParticipantType.Individual) && (pType != ParticipantType.Corporation)) {
      revert InvalidParticipantType(pType);
    }

    address signer = ECDSA.recover(
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256("KYCVerification(uint8 participantType,address participant,bytes32 kyc,uint256 nonce)"),
            pType,
            approving,
            kycHash,
            0 // For now, don't allow updating KYC hashes
          )
        )
      ),
      signature
    );
    if (participant[signer] != ParticipantType.KYC) {
      revert InvalidKYCSignature(signer, participant[signer]);
    }

    if (participant[approving] != ParticipantType.Null) {
      revert ParticipantAlreadyApproved(approving);
    }

    _changeParticipantAndKYC(approving, pType, kycHash);
    if (pType == ParticipantType.Governor) {
      governor[approving] = GovernorStatus.Active;
    }
  }
}
