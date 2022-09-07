const { ethers } = require("hardhat");
const { expect } = require("chai");
const deployBeaconProxy = require("../../scripts/deployBeaconProxy.js")
const deployBeacon = require("../../scripts/deployBeacon.js");
const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { ProposalState, FrabricProposalType, ParticipantType } = require("../common.js");

let addresses;
let frabric, tx;

describe("InitialFrabric", accounts => {
  before(async () => {
    genesis = (await ethers.getSigners()).splice(1, 5);

    const { frbc } = await FrabricERC20.deployFRBC(
      (await (await ethers.getContractFactory("TestERC20")).deploy("Test Token", "TEST")).address
    );
    let  queuePeriod = 60 * 60 * 24 * 2;
    let  lapsePeriod = 60 * 60 * 24 * 2;
    let  votingPeriod = 60 * 60 * 24 * 7;
    const InitialFrabric = await ethers.getContractFactory("InitialFrabric");
    const beacon = await deployBeacon("single", InitialFrabric);
    frabric = await deployBeaconProxy(beacon, InitialFrabric,
      [],
        {initializer: false}
    );

    addresses = genesis.map(signer => signer.address);

    tx = await frabric.initialize(frbc.address, addresses, votingPeriod, queuePeriod, lapsePeriod);
  });

  it("should have initialized correctly", async () => {
    for (const address of addresses) {
      await expect(tx).to.emit(frabric, "ParticipantChange").withArgs(ParticipantType.Genesis, address);
      expect(await frabric.participant(address)).to.equal(ParticipantType.Genesis);
    }
  });
});
