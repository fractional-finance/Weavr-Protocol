const { ethers } = require("hardhat");
const { assert, expect } = require("chai");

const deployTestThread = require("../scripts/deployTestThread.js");
const common = require("../common.js")
const { GovernorStatus, ThreadProposalType, completeProposal } = common;

let signers, governor, participant;
let frabric, token;
let erc20, thread, nextID;

// TODO: Test supermajority is used where it should be

describe("Thread", async () => {
  before(async () => {
    signers = await ethers.getSigners();
    const owner = signers.splice(0, 1)[0];
    governor = signers.splice(0, 1)[0];
    // { token, frabric, erc20, beacon, thread }
    const contracts = await deployTestThread(governor.address); // TODO: Verify init
    frabric = contracts.frabric; // Actually a TestFrabric
    token = contracts.token;
    erc20 = contracts.erc20;
    thread = contracts.thread;

    // Move the balance from the owner (deployer)
    participant = signers.splice(1, 1)[0];
    await frabric.setWhitelisted(participant.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await token.transfer(participant.address, await token.balanceOf(owner.address));
    await erc20.transfer(participant.address, (await erc20.balanceOf(owner.address)).sub(1));
    thread = thread.connect(participant);

    nextID = 0;
  });

  it("shouldn't let anyone propose", async () => {
    assert(!(await thread.canPropose(signers[0].address)));
  });

  it("should let the Frabric and Governor propose", async () => {
    assert(await thread.canPropose(await thread.frabric()));
    assert(await thread.canPropose(governor.address));
  });

  it("should let whitelisted token holders propose", async () => {
    // signers[0] will be burnt so remove them from signers
    const listTest = signers.splice(0, 1)[0];
    await frabric.setWhitelisted(listTest.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    // Whitelisted yet not holder
    assert(!(await thread.canPropose(listTest.address)));
    await erc20.transfer(listTest.address, 1);
    // Whitelisted and holder
    assert(await thread.canPropose(listTest.address));
    // Not whitelisted yet holder
    await frabric.remove(listTest.address);
    assert(!(await thread.canPropose(listTest.address)));
  });

  it("should't let you remove Frabric/Timelock/Crowdfund", async () => {
    // TODO
  });

  it("should allow changing the descriptor", async () => {
    const pID = nextID;
    nextID++;
    const oldDescriptor = await thread.descriptor();
    const newDescriptor = "0x" + (new Buffer.from("new IPFS").toString("hex")).repeat(4);
    expect(
      await thread.proposeDescriptorChange(
        "0x" + (new Buffer.from("new IPFS").toString("hex")).repeat(4),
        ethers.utils.id("Proposing a new descriptor")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        ThreadProposalType.DescriptorChange,
        participant.address,
        ethers.utils.id("Proposing a new descriptor")
      )
      .to.emit("DescriptorChangeProposed").withArgs(pID, newDescriptor);
    expect(
      await completeProposal(thread, pID)
    ).to.emit("DescriptorChange").withArgs(oldDescriptor, newDescriptor);
    expect(await thread.descriptor()).to.equal(newDescriptor);
  });

  it("should allow changing the Frabric", async () => {
    // Take a snapshot so we can continue using the existing TestFrabric
    let snapshot = await common.snapshot();

    const pID = nextID;
    // Doesn't increment nextID due to using a snapshot

    otherFrabric = await (await ethers.getContractFactory("TestFrabric")).deploy();
    otherFrabric.setGovernor(signers[0].address, GovernorStatus.Active);
    expect(
      await thread.proposeFrabricChange(
        otherFrabric.address,
        signers[0].address,
        ethers.utils.id("Proposing a new Frabric")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        ThreadProposalType.FrabricChange,
        participant.address,
        ethers.utils.id("Proposing a new Frabric")
      )
      .to.emit("FrabricChangeProposed").withArgs(pID, otherFrabric.address, signers[0].address);

    // Make sure the new governor is the only party which can execute this
    // This signals their consent
    await expect(
      completeProposal(thread, pID)
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${signers[0].address}")`);
    expect(
      await thread.connect(signers[0]).completeProposal(pID)
    )
      .to.emit("FrabricChange").withArgs(frabric.address, otherFrabric.address)
      .to.emit("GovernorChange").withArgs(governor.address, signers[0].address);
    expect(await thread.frabric()).to.equal(otherFrabric.address);
    expect(await thread.governor()).to.equal(signers[0].address);
    expect(await erc20.parent()).to.equal(otherFrabric.address);

    await common.revert(snapshot);
  });

  it("should allow changing the Governor", async () => {
    const pID = nextID;
    nextID++;

    frabric.setGovernor(signers[0].address, GovernorStatus.Active);
    expect(
      await thread.proposeGovernorChange(
        signers[0].address,
        ethers.utils.id("Proposing a new Governor")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        ThreadProposalType.GovernorChange,
        participant.address,
        ethers.utils.id("Proposing a new Governor")
      )
      .to.emit("GovernorChangeProposed").withArgs(pID, signers[0].address);

    await expect(
      completeProposal(thread, pID)
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${signers[0].address}")`);
    expect(
      await thread.connect(signers[0]).completeProposal(pID)
    ).to.emit("GovernorChange").withArgs(governor.address, signers[0].address);
    expect(await thread.governor()).to.equal(signers[0].address);

    governor = signers.splice(0, 1)[0];
  });

  it("should allow leaving the ecosystem", async () => {
    // TODO
  });

  it("should allow dissolving", async () => {
    const pID = nextID;
    nextID++;

    expect(
      await thread.proposeDissolution(
        token.address,
        777,
        ethers.utils.id("Proposing a dissolution")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        ThreadProposalType.Dissolution,
        participant.address,
        ethers.utils.id("Proposing a dissolution")
      )
      .to.emit("DissolutionProposed").withArgs(pID, token.address, 777);

    await token.connect(participant).approve(thread.address, 777);

    // Make sure the governor is the only party which can executes this
    // This confirms they'll manage the underlying asset accordingly
    // They may refuse to, without being malicious, if this process was sabotaged
    // In that case, the Frabric would arbitrate
    await expect(
      completeProposal(thread, pID)
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${governor.address}")`);
    expect(
      await thread.connect(governor).completeProposal(pID)
    )
      .to.emit("Transfer").withArgs(participant.address, thread.address, 777)
      .to.emit("Paused")
      .to.emit("Transfer").withArgs(thread.address, erc20.address, 777)
      .to.emit("Distribution").withArgs(0, token.address, 777);
    assert(await erc20.paused());
  });
});
