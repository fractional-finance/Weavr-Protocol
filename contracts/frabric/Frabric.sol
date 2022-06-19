// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/** 
 * @title Frabric decentralized Real estate market
 * @author Fractional Finance
 * @notice This contract implements the FrabricDAO
 * @dev This is an Upgradeable Contract
 */

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
  
 /**
  * @dev Participant struct definition
  * @param pType (ParticipantType) Type of participant
  * @param addr (address) Address of the participant
  */
  struct Participant {
    ParticipantType pType;
    address addr;
  }
  /// @dev The proposal structs are private as their events are easily grabbed and contain the needed information
  mapping(uint256 => Participant) private _participants;

 /**
  * @dev BondRemoval struct definition
  * @param governor (address) Address of the governor
  * @param slash (bool) Slash funds option
  * @param addr (uint256) Amount to be slashed
  */
  struct BondRemoval {
    address governor;
    bool slash;
    uint256 amount;
  }
  mapping(uint256 => BondRemoval) private _bondRemovals;

 /**
  * @dev Thread struct definition
  * @param variant (uint8) Variant of the Thread smart contract
  * @param governor (address) Address of the governor
  * @param symbol (string) Symbol of the Thread Token
  * @param descriptor Thread's descriptor
  * @param name (string) Name of the Thread Token
  * @param data (bytes) Thread's data 
  */
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

  /**
  * @dev ThreadProposal struct definition
  * @param thread (address) Address of the Thread
  * @param select (bytes4) ThreadProposal's selector 
  * @param data (bytes) ThreadProposal's data 
  */
  struct ThreadProposalStruct {
    address thread;
    bytes4 selector;
    bytes data;
  }
  mapping(uint256 => ThreadProposalStruct) private _threadProposals;

  mapping(address => uint256) public override vouchers;

  mapping(uint16 => bytes4) private _proposalSelectors;

  /// @notice This funtion is used to validate an upgrade.
  /// @param _version (uint256) Version to be validated 
  /// @param data     (bytes) AbiEncoded _bond and _threadDeployer addresses/
  function validateUpgrade(uint256 _version, bytes calldata data) external view override {
    if (_version != 2) {
      revert InvalidVersion(_version, 2);
    }

    (address _bond, address _threadDeployer, ) = abi.decode(data, (address, address, address));
    if (!_bond.supportsInterface(type(IBondCore).interfaceId)) {
      revert UnsupportedInterface(_bond, type(IBondCore).interfaceId);
    }
    if (!_threadDeployer.supportsInterface(type(IThreadDeployer).interfaceId)) {
      revert UnsupportedInterface(_threadDeployer, type(IThreadDeployer).interfaceId);
    }
  }

  
  /// @param kyc (address) Address of the wallet to be whitelisted 
  function _addKYC(address kyc) private {
    IFrabricWhitelistCore(erc20).whitelist(kyc);
    participant[kyc] = ParticipantType.KYC;
    emit ParticipantChange(ParticipantType.KYC, kyc);
    IFrabricWhitelistCore(erc20).setKYC(kyc, keccak256(abi.encodePacked("KYC ", kyc)), 0);
  }

  /// @notice This funtion triggers the upgrade to a new version.
  /// @param _version (uint256) Version to upgrade to 
  /// @param data (bytes) AbiEncoded _bond, _threadDeployer and kyc addresses/
  function upgrade(uint256 _version, bytes calldata data) external override {
    address beacon = StorageSlot.getAddressSlot(
      /// @dev Beacon storage slot
      0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50
    ).value;
    if (msg.sender != beacon) {
      revert NotBeacon(msg.sender, beacon);
    }

   /**
    * @dev While this isn't possible for this version (2), it is possible if this was
    * code version 3 yet triggerUpgrade was never called for version 2
    * In that scenario, this could be called with version 2 data despite expecting
    * version 3 data
    */
    if (_version != (version + 1)) {
      revert InvalidVersion(_version, version + 1);
    }
    version++;

   /** 
    * @dev Drop support for IInitialFrabric
    * While we do still match it, and it shouldn't hurt to keep it around,
    * we never want to encourage its usage, nor do we want to forget about it
    * if we ever do introduce an incompatibility
    */
    supportsInterface[type(IInitialFrabric).interfaceId] = false;

    /// @dev Add support for the new Frabric interfaces
    supportsInterface[type(IFrabricCore).interfaceId] = true;
    supportsInterface[type(IFrabric).interfaceId] = true;

    /// @dev Set bond, threadDeployer, and an initial KYC
    address kyc;
    (bond, threadDeployer, kyc) = abi.decode(data, (address, address, address));

    _addKYC(kyc);

    _proposalSelectors[uint16(CommonProposalType.Paper)       ^ commonProposalBit] = IFrabricDAO.proposePaper.selector;
    _proposalSelectors[uint16(CommonProposalType.Upgrade)     ^ commonProposalBit] = IFrabricDAO.proposeUpgrade.selector;
    _proposalSelectors[uint16(CommonProposalType.TokenAction) ^ commonProposalBit] = IFrabricDAO.proposeTokenAction.selector;

    _proposalSelectors[uint16(IThread.ThreadProposalType.DescriptorChange)] = IThread.proposeDescriptorChange.selector;
    _proposalSelectors[uint16(IThread.ThreadProposalType.GovernorChange)]   = IThread.proposeGovernorChange.selector;
    _proposalSelectors[uint16(IThread.ThreadProposalType.Dissolution)]      = IThread.proposeDissolution.selector;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Frabric") initializer {
    /// @dev Only set in the constructor as this has no value being in the live contract
    supportsInterface[type(IUpgradeable).interfaceId] = true;
  }

  /// @notice This function checks if the proposer is allow to make a proposal.
  /// @param proposer (address) Proposer's address.
  function canPropose(address proposer) public view override(DAO, IDAOCore) returns (bool) {
    return uint8(participant[proposer]) >= uint8(ParticipantType.Genesis);
  }

  /// @notice This function allows to propose a new partecipant to the FrabricDAO.
  /// @param participantType (ParticipantType) Type of the partecipant.
  /// @param _participant (address) New participant's address.
  /// @param info (bytes32) Proposal's information.
  /// @return id of the new participant (uint256).
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

  /// @notice Propose a Bond Removal.
  /// @param _governor (address) Governor's address
  /// @param slash (bool) Slash active/inactive
  /// @param amount (uint256) Amount of bond to be removed
  /// @param info (bytes32) Proposal's information
  /// @return id of the proposal (uint256)
  function proposeBondRemoval(
    address _governor,
    bool slash,
    uint256 amount,
    bytes32 info
  ) external override returns (uint256 id) {
    id = _createProposal(uint16(FrabricProposalType.RemoveBond), false, info);
    _bondRemovals[id] = BondRemoval(_governor, slash, amount);
    if (governor[_governor] < GovernorStatus.Active) {
     /** 
      * @dev Arguably a misuse as this actually checks they were never an active governor
      * Not that they aren't currently an active governor, which the error name suggests
      * This should be better to handle from an integration perspective however
      */
      revert NotActiveGovernor(_governor, governor[_governor]);
    }
    emit BondRemovalProposal(id, _governor, slash, amount);
  }

  /// @notice This function allow to propose a new Thread
  /// @param variant    (uint8) Variant of the Thread contract
  /// @param name       (string) Name of the Thread
  /// @param symbol     (string) Symbol of the Thread
  /// @param descriptor (bytes32) ?
  /// @param data       (bytes) ?
  /// @param info       (bytes32) Proposal's information
  /// @return id of the proposal
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

    /// @dev Doesn't check for being alphanumeric due to iteration costs
    if (
      (bytes(name).length < 6) || (bytes(name).length > 64) ||
      (bytes(symbol).length < 2) || (bytes(symbol).length > 5)
    ) {
      revert InvalidName(name, symbol);
    }
   /** 
    * @dev Validate the data now before creating the proposal
    * ThreadProposal doesn't have this same level of validation yet not only are
    * Threads a far more integral part of the system, ThreadProposal deals with an enum
    * for proposal type. This variant field is a uint256 which has a much larger impact scope
    */
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

 /**
  * @dev This does assume the Thread's API meets expectations compiled into the Frabric
  * They can individually change their Frabric, invalidating this entirely, or upgrade their code, potentially breaking specific parts
  * These are both valid behaviors intended to be accessible by Threads
  * @notice This function allow to propose a new Thread's proposal
  * @param thread         (uint8) Variant of the Thread contract
  * @param _proposalType  (string) Name of the Thread
  * @param data           (bytes) ?
  * @param info           (bytes32) Proposal's information
  * @return id of the proposal
  */
  function proposeThreadProposal(
    address thread,
    uint16 _proposalType,
    bytes calldata data,
    bytes32 info
  ) external returns (uint256 id) {
    /// @dev Technically not needed given we check for interface support, yet a healthy check to have
    if (IComposable(thread).contractName() != keccak256("Thread")) {
      revert DifferentContract(IComposable(thread).contractName(), keccak256("Thread"));
    }

   /** 
    * @dev Lock down the selector to prevent arbitrary calls
    * While data is still arbitrary, it has reduced scope thanks to this, and can only be decoded in expected ways
    * data isn't validated to be technically correct as the UI is trusted to sanity check it
    * and present it accurately for humans to deliberate on
    */
    bytes4 selector;
    if (_isCommonProposal(_proposalType)) {
      if (!thread.supportsInterface(type(IFrabricDAO).interfaceId)) {
        revert UnsupportedInterface(thread, type(IFrabricDAO).interfaceId);
      }
    } else {
      if (!thread.supportsInterface(type(IThread).interfaceId)) {
        revert UnsupportedInterface(thread, type(IThread).interfaceId);
      }
    }
    selector = _proposalSelectors[_proposalType];
    if (selector == bytes4(0)) {
      revert UnhandledEnumCase("Frabric proposeThreadProposal", _proposalType);
    }

    id = _createProposal(uint16(FrabricProposalType.ThreadProposal), false, info);
    _threadProposals[id] = ThreadProposalStruct(thread, selector, data);
    emit ThreadProposalProposal(id, thread, _proposalType, data);
  }

  function _participantRemoval(address _participant) internal override {
    if (governor[_participant] != GovernorStatus.Null) {
      governor[_participant] = GovernorStatus.Removed;
    }
    participant[_participant] = ParticipantType.Removed;
    emit ParticipantChange(ParticipantType.Removed, _participant);
  }

  function _completeSpecificProposal(uint256 id, uint256 _pType) internal override {
    FrabricProposalType pType = FrabricProposalType(_pType);
    if (pType == FrabricProposalType.Participant) {
      Participant storage _participant = _participants[id];
     /** 
      * @dev This check also exists in proposeParticipant, yet that doesn't prevent
      * the same participant from being proposed multiple times simultaneously
      * This is an edge case which should never happen, yet handling it means
      * checking here to ensure if they already exist, they're not overwritten
      * While we could error here, we may as well delete the invalid proposal and move on with life
      */
      if (participant[_participant.addr] != ParticipantType.Null) {
        delete _participants[id];
        return;
      }

      if (_participant.pType == ParticipantType.KYC) {
        _addKYC(_participant.addr);
        delete _participants[id];
      } else {
        /// @dev Whitelist them until they're KYCd
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
     /** 
      * @dev This governor may no longer be viable for usage yet the Thread will check
      * When proposing this proposal type, we validate we upgraded which means this has been set
      */
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
        revert ExternalCallFailed(proposal.thread, proposal.selector, data);
      }
      delete _threadProposals[id];
    } else {
      revert UnhandledEnumCase("Frabric _completeSpecificProposal", _pType);
    }
  }

  /// @notice This function allow to vouch a new participant
  /// @param _participant    (uint8) Variant of the Thread contract
  /// @param signature       (bytes) 
  function vouch(address _participant, bytes calldata signature) external override {
   /**
    * @dev Places signer in a variable to make the information available for the error
    * While generally, the errors include an abundance of information with the expectation they'll be caught in a call,
    * and even if they are executed on chain, we don't care about the increased gas costs for the extreme minority,
    * this calculation is extensive enough it's worth the variable (which shouldn't even change gas costs?)
    */
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
      if (vouchers[signer] == 6) {
        revert OutOfVouchers(signer);
      }
      vouchers[signer] += 1;
    }

    /// @dev The fact whitelist can only be called once for a given participant makes this secure against replay attacks
    IFrabricWhitelistCore(erc20).whitelist(_participant);
    emit Vouch(signer, _participant);
  }

  /// @notice This function allows to approve a new Participant
  /// @param pType (ParticipantType) Type of participant
  /// @param approving (address) Participant to be approved
  /// @param kycHash (bytes32) Is a zk-proof of the  KYC process
  /// @param signature (bytes) Signature of the ...
  function approve(
    ParticipantType pType,
    address approving,
    bytes32 kycHash,
    bytes calldata signature
  ) external override {
    if ((pType == ParticipantType.Null) && passed[uint160(approving)]) {
      address temp = _participants[uint160(approving)].addr;
      pType = _participants[uint160(approving)].pType;
      delete _participants[uint160(approving)];
      approving = temp;
    } else if ((pType != ParticipantType.Individual) && (pType != ParticipantType.Corporation)) {
      revert InvalidParticipantType(pType);
    } else {
      pType = pType;
    }

    address signer = ECDSA.recover(
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256("KYCVerification(uint8 participantType,address participant,bytes32 kyc,uint256 nonce)"),
            pType,
            approving,
            kycHash,
            0 /// @dev For now, don't allow updating KYC hashes
          )
        )
      ),
      signature
    );
    if (participant[signer] != ParticipantType.KYC) {
      revert InvalidKYCSignature(signer, participant[signer]);
    }

    participant[approving] = pType;
    if (pType == ParticipantType.Governor) {
      governor[approving] = GovernorStatus.Active;
    }
    emit ParticipantChange(pType, approving);

    IFrabricWhitelistCore(erc20).setKYC(approving, kycHash, 0);
    emit KYC(signer, approving);
  }
}
