const { ethers } = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const { expect } = require("chai");

const deployBeacon = require("../../scripts/deployBeacon.js");
const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { ProposalState, ParticipantType } = require("../common.js");

let addresses, root;
let frabric, tx;

describe("InitialFrabric", accounts => {
  before(async () => {
    genesis = (await ethers.getSigners()).splice(1, 5);

    const { frbc } = await FrabricERC20.deployFRBC(ethers.constants.AddressZero);

    const InitialFrabric = await ethers.getContractFactory("InitialFrabric");
    const beacon = await deployBeacon("single", InitialFrabric);
    frabric = await upgrades.deployBeaconProxy(
      beacon,
      InitialFrabric,
      [],
      { initializer: false }
    );

    addresses = genesis.map(signer => signer.address);
    root = (
      new MerkleTree(
        addresses.map(address => address + "000000000000000000000000"),
        ethers.utils.keccak256,
        { sortPairs: true }
      )
    ).getHexRoot();

    tx = await frabric.initialize(frbc.address, addresses, root);
  });

  it("should have initialized correctly", async () => {
    // Fake proposal for participation addition
    await expect(tx).to.emit(frabric, "Proposal");
    await expect(tx).to.emit(frabric, "ProposalStateChange").withArgs(0, ProposalState.Active);
    await expect(tx).to.emit(frabric, "ProposalStateChange").withArgs(0, ProposalState.Queued);
    await expect(tx).to.emit(frabric, "ProposalStateChange").withArgs(0, ProposalState.Executed);
    await expect(tx).to.emit(frabric, "ProposalStateChange").withArgs(0, ProposalState.Executed);
    await expect(tx).to.emit(frabric, "ParticipantsProposal").withArgs(0, ParticipantType.Genesis, root);
    for (const address of addresses) {
      // Per-participant variables
      await expect(tx).to.emit(frabric, "ParticipantChange").withArgs(address, ParticipantType.Genesis);
      expect(await frabric.participant(address)).to.equal(ParticipantType.Genesis);
    }
  });
});
