const { ethers } = require("hardhat");
const { assert, expect } = require("chai");

const deployTestThread = require("../scripts/deployTestThread.js");
const common = require("../common.js")
const { GovernorStatus, ThreadProposalType } = common;

let signers, governor, participant;
// Actually a TestFrabric
let frabric, token;
let erc20, thread;

// TODO: Test supermajority is used where it should be

// Test only the governor can complete this proposal
async function onlyGovernor(thread, proposal, args, governor) {
  // Propose it
  const { id } = await common.propose(thread, proposal, args);
  // Queue it, and attempt completion with the default signer
  await expect(
    common.queueAndComplete(thread, id)
  ).to.be.revertedWith(`NotGovernor("${thread.signer.address}", "${governor.address}")`);
  // Explicitly complete it with the governor
  return await thread.connect(governor).completeProposal(id);
}

describe("Thread", async () => {
  before(async () => {
    signers = await ethers.getSigners();
    const owner = signers.splice(0, 1)[0];
    governor = signers.splice(0, 1)[0];

    ({ token, frabric, erc20, beacon, thread } = await deployTestThread(governor.address)); // TODO: Verify init
    beacon.implementation = beacon["implementation(address)"];

    // Move the balance from the owner (deployer)
    participant = signers.splice(1, 1)[0];
    await frabric.whitelist(participant.address);
    await token.transfer(participant.address, await token.balanceOf(owner.address));
    await erc20.transfer(participant.address, (await erc20.balanceOf(owner.address)).sub(1));
    thread = thread.connect(participant);
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
    await frabric.whitelist(listTest.address);
    // Whitelisted yet not holder
    assert(!(await thread.canPropose(listTest.address)));
    await erc20.transfer(listTest.address, 1);
    // Whitelisted and holder
    assert(await thread.canPropose(listTest.address));
    // Not whitelisted yet holder
    await frabric.remove(listTest.address);
    assert(!(await thread.canPropose(listTest.address)));
  });

  it("shouldn't let you upgrade to an independent piece of code before leaving", async () => {
    const newCode = await (await ethers.getContractFactory("Thread")).deploy();
    await expect(
      thread.proposeUpgrade(
        beacon.address,
        thread.address,
        1,
        newCode.address,
        "0x",
        ethers.utils.id("Upgrade Independent")
      )
    ).to.be.revertedWith(`ProposingUpgrade("${beacon.address}", "${thread.address}", "${newCode.address}")`);
  });

  it("should let you upgrade to the current piece of code", async () => {
    const code = await beacon.implementation(thread.address);
    expect(await beacon.implementations(thread.address)).to.equal(ethers.constants.AddressZero);
    await expect(
      await common.proposal(
        thread,
        "Upgrade",
        [beacon.address, thread.address, 1, code, "0x"]
      )
    );
    expect(await beacon.implementations(thread.address)).to.equal(code);
  });

  // This is actually a test on the legitimacy of the deployment which specifies
  // irremovable contracts, which deployTestThread only specifies one of (the Frabric)
  // Still checks that irremovable contracts can't be removed, with ThreadDeployer's
  // test picking up the rest of the slack
  it("should't let you remove the Frabric", async () => {
    await expect(
      thread.proposeParticipantRemoval(frabric.address, 0, [], ethers.utils.id("Proposing removing the Frabric"))
    ).to.be.revertedWith(`Irremovable("${frabric.address}")`);
  });

  it("should allow changing the descriptor", async () => {
    const oldDescriptor = await thread.descriptor();
    const newDescriptor = "0x" + (new Buffer.from("new IPFS").toString("hex")).repeat(4);
    await expect(
      (await common.proposal(thread, "DescriptorChange", [newDescriptor])).tx
    ).to.emit(thread, "DescriptorChange").withArgs(oldDescriptor, newDescriptor);
    expect(await thread.descriptor()).to.equal(newDescriptor);
  });

  it("should allow changing the Frabric", async () => {
    // Take a snapshot so we can continue using the existing TestFrabric
    let snapshot = await common.snapshot();

    try {
      otherFrabric = await (await ethers.getContractFactory("TestFrabric")).deploy();
      otherFrabric.setGovernor(signers[0].address, GovernorStatus.Active);

      // Make sure the new governor is the only party which can execute this
      // This signals their consent
      const tx = await onlyGovernor(thread, "FrabricChange", [otherFrabric.address, signers[0].address], signers[0]);
      await expect(tx).to.emit(thread, "FrabricChange").withArgs(frabric.address, otherFrabric.address)
      await expect(tx).to.emit(thread, "GovernorChange").withArgs(governor.address, signers[0].address);
      await expect(await thread.frabric()).to.equal(otherFrabric.address);
      await expect(await thread.governor()).to.equal(signers[0].address);
      await expect(await erc20.parent()).to.equal(otherFrabric.address);
    } catch (e) {
      throw e;
    } finally {
      await common.revert(snapshot);
    }
  });

  it("should allow changing the Governor", async () => {
    frabric.setGovernor(signers[0].address, GovernorStatus.Active);

    await expect(
      onlyGovernor(thread, "GovernorChange", [signers[0].address], signers[0])
    ).to.emit(thread, "GovernorChange").withArgs(governor.address, signers[0].address);
    expect(await thread.governor()).to.equal(signers[0].address);

    governor = signers.splice(0, 1)[0];
  });

  it("should allow leaving the ecosystem", async () => {
    // TODO
  });

  it("should allow dissolving", async () => {
    await token.connect(participant).approve(thread.address, 777);

    // Make sure the governor is the only party which can executes this
    // This confirms they'll manage the underlying asset accordingly
    // They may refuse to, without being malicious, if this process was sabotaged
    // In that case, the Frabric would arbitrate

    const tx = await onlyGovernor(thread, "Dissolution", [token.address, 777], governor);
    // The Transfer events fail to match due to waffle's incompetency
    // There doesn't seem to be a specifically matching open issue and I don't
    // have time to debug this right now
    // Paused/Distributed still matching means it's anyone's guess why
    //await expect(tx).to.emit(erc20, "Transfer").withArgs(participant.address, thread.address, 777);
    await expect(tx).to.emit(erc20, "Paused");
    //await expect(tx).to.emit(erc20, "Transfer").withArgs(thread.address, erc20.address, 777);
    await expect(tx).to.emit(erc20, "Distributed").withArgs(0, token.address, 777);

    // Compensate for waffle's incompetency
    let expected = [[participant.address, thread.address, 777], [thread.address, erc20.address, 777]];
    for (let event of (await (await tx).wait()).events) {
      try {
        event = erc20.interface.parseLog(event);
      } catch { continue; }

      if (event.name === "Transfer") {
        expect(event.args.from).to.equal(expected[0][0]);
        expect(event.args.to).to.equal(expected[0][1]);
        expect(event.args.value).to.equal(expected[0][2]);
        expected.splice(0, 1);
      }
    }
    expect(expected.length).to.be.equal(0);

    assert(await erc20.paused());
  });
});
