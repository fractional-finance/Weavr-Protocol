const { ethers } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { ProposalState, VoteDirection, impermanent, increaseTime } = require("../common.js");

const TYPE = 255;
const INFO = ethers.utils.id("info");

let signers, deployer, other;
let frbc, dao;

let end;

describe("DAO", () => {
  before(async () => {
    signers = await ethers.getSigners();
    ([ deployer, other ] = signers.splice(0, 2));

    const usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");
    ({ frbc } = await FrabricERC20.deployWEAV(usd.address));
    await frbc.mint(deployer.address, 100);
    await frbc.setKYC(deployer.address, ethers.utils.id("deployer"), 0);
    dao = await (await ethers.getContractFactory("TestDAO")).deploy(frbc.address);
    await frbc.whitelist(dao.address);
  });

  it("should have initialized correctly", async () => {
    expect(await dao.erc20()).to.equal(frbc.address);
    expect(await dao.votingPeriod()).to.equal(3 * 24 * 60 * 60);
    expect(await dao.queuePeriod()).to.equal(2 * 24 * 60 * 60);
  });

  it("should have 10% required participation", async () => {
    expect(await dao.requiredParticipation()).to.equal(10);
  });

  it("shouldn't expect participation from tokens it holds", impermanent(async () => {
    await frbc.transfer(dao.address, 10);
    expect(await dao.requiredParticipation()).to.equal(9);
  }));

  it("should check canPropose", async () => {
    await expect(
      dao.connect(other).propose(TYPE, false, INFO)
    ).to.be.revertedWith(`NotWhitelisted("${other.address}")`);
  });

  it("should create proposals and automatically vote", async () => {
    // Prep code for other tests
    await frbc.whitelist(other.address);
    await frbc.setKYC(other.address, ethers.utils.id("kyc"), 0);
    await frbc.transfer(other.address, 8);

    const tx = await dao.propose(TYPE, false, INFO);
    await expect(tx).to.emit(dao, "Proposal").withArgs(0, TYPE, deployer.address, false, INFO);
    await expect(tx).to.emit(dao, "ProposalStateChange", 0, ProposalState.Active);
    // 10, not 92, due to the 10% vote cap
    await expect(tx).to.emit(dao, "Vote").withArgs(0, VoteDirection.Yes, deployer.address, 10);

    assert(await dao.proposalActive(0));
    const block = (await waffle.provider.getBlock("latest"));
    end = (await dao.votingPeriod()).add(block.timestamp);
    expect(await dao.supermajorityRequired(0)).to.equal(false);
    expect(await dao.voteBlock(0)).to.equal(block.number - 1);
    expect(await dao.netVotes(0)).to.equal(10);
    expect(await dao.totalVotes(0), 10);
    expect(await dao.voteRecord(0, deployer.address)).to.equal(10);
  });

  it("should create proposals requiring a supermajority", async () => {
    const tx = await dao.propose(TYPE, true, INFO);
    await expect(tx).to.emit(dao, "Proposal").withArgs(1, TYPE, deployer.address, true, INFO);
    assert(await dao.supermajorityRequired(1));
    await expect(tx).to.emit(dao, "ProposalStateChange", 1, ProposalState.Active);
    await expect(tx).to.emit(dao, "Vote").withArgs(1, VoteDirection.Yes, deployer.address, 10);
  });

  it("should let you partially vote", async () => {
    await expect(
      await dao.connect(other).vote([0], [-5])
    ).to.emit(dao, "Vote").withArgs(0, VoteDirection.No, other.address, 5);
    expect(await dao.netVotes(0)).to.equal(5);
    expect(await dao.totalVotes(0), 15);
    expect(await dao.voteRecord(0, other.address)).to.equal(-5);
  });

  // Also tests re-voting
  it("should let you vote with more than you have yet correct it", async () => {
    // Sanity check to ensure this can't just use the 10% cap
    assert(9 < (parseInt(await frbc.totalSupply()) / 10));

    // Positive variant
    await expect(
      await dao.connect(other).vote([0], [9])
    ).to.emit(dao, "Vote").withArgs(0, VoteDirection.Yes, other.address, 8);
    expect(await dao.netVotes(0)).to.equal(18);
    expect(await dao.totalVotes(0), 18);
    expect(await dao.voteRecord(0, other.address)).to.equal(8);

    // Negative variant
    await expect(
      await dao.connect(other).vote([0], [-9])
    ).to.emit(dao, "Vote").withArgs(0, VoteDirection.No, other.address, 8);
    // As a note, 2 < (20 / 6), so this is majority yet not supermajority
    expect(await dao.netVotes(0)).to.equal(2);
    expect(await dao.totalVotes(0), 18);
    expect(await dao.voteRecord(0, other.address)).to.equal(-8);
  });

  // TODO: Batch voting

  it("shouldn't let anyone withdraw proposals", async () => {
    await expect(
      dao.connect(other).withdrawProposal(0)
    ).to.be.revertedWith(`Unauthorized("${other.address}", "${deployer.address}")`);
  });

  it("should let the proposal creator withdraw an active proposal ", impermanent(async () => {
    await expect(
      await dao.withdrawProposal(0)
    ).to.emit(dao, "ProposalStateChange").withArgs(0, ProposalState.Cancelled);
    expect(await dao.proposalActive(0)).to.equal(false);
  }));

  it("shouldn't let you queue proposals still being voted on", async () => {
    let time = (await waffle.provider.getBlock("latest")).timestamp + 1;
    await expect(dao.queueProposal(0)).to.be.revertedWith(`ActiveProposal(0, ${time}, ${end})`);
  });

  it("shouldn't let you queue net positive proposals which require a supermajority", impermanent(async () => {
    await expect(
      await dao.connect(other).vote([1], [-8])
    ).to.emit(dao, "Vote").withArgs(1, VoteDirection.No, other.address, 8);
    await increaseTime(parseInt(await dao.votingPeriod()));
    await expect(
      dao.queueProposal(1)
    ).to.be.revertedWith(`ProposalFailed(1, 2)`);
  }));

  it("should let you queue passing proposals", async () => {
    await increaseTime(parseInt(await dao.votingPeriod()));
    await expect(
      await dao.queueProposal(0)
    ).to.emit(dao, "ProposalStateChange").withArgs(0, ProposalState.Queued);
    end = (await dao.queuePeriod()).add((await waffle.provider.getBlock("latest")).timestamp);
  });

  it("should let you queue passing supermajority proposals", async () => {
    await expect(
      await dao.queueProposal(1)
    ).to.emit(dao, "ProposalStateChange").withArgs(1, ProposalState.Queued);
  });

  // TODO: Negative net (somewhat tested already by the negative supermajority test)

  it("should let you withdraw queued proposals", impermanent(async () => {
    await expect(
      await dao.withdrawProposal(0)
    ).to.emit(dao, "ProposalStateChange").withArgs(0, ProposalState.Cancelled);
    expect(await dao.proposalActive(0)).to.equal(false);
  }));

  it("shouldn't let you cancel proposals which have enough votes", async () => {
    await expect(
      dao.cancelProposal(0, [])
    ).to.be.revertedWith(`ProposalPassed(0, 2)`);
  });

  it("shouldn't let you cancel proposals with voters who voted no", impermanent(async () => {
    await expect(
      dao.cancelProposal(0, [other.address])
    ).to.be.revertedWith(`NotYesVote(0, "${other.address}")`);
  }));

  it("shouldn't let you cancel proposals with repeated voters", impermanent(async () => {
    await expect(
      dao.cancelProposal(0, [deployer.address, deployer.address])
    ).to.be.revertedWith(`UnsortedVoter("${deployer.address}")`);
  }));

  it("should let you cancel proposals which no longer have enough votes", impermanent(async () => {
    await frbc.transfer(dao.address, await frbc.balanceOf(deployer.address));
    await expect(
      await dao.cancelProposal(0, [deployer.address])
    ).to.emit(dao, "ProposalStateChange").withArgs(0, ProposalState.Cancelled);
    expect(await dao.proposalActive(0)).to.equal(false);
  }));

  it("shouldn't let you complete proposals which are still queued", async () => {
    let time = (await waffle.provider.getBlock("latest")).timestamp + 1;
    await expect(
      dao.completeProposal(0, "0x")
    ).to.be.revertedWith(`StillQueued(0, ${time}, ${end})`);
  });

  it("should let you complete proposals", async () => {
    await increaseTime(parseInt(await dao.queuePeriod()));
    await expect(
      await dao.completeProposal(0, "0x")
    ).to.emit(dao, "Completed").withArgs(0, TYPE);
    assert(await dao.passed(0));
  });

  it("should delete the proposal, which leaves behind the vote map", async () => {
    // This first check is pointless as this field is already false
    expect(await dao.supermajorityRequired(0)).to.equal(false);
    expect(await dao.voteBlock(0)).to.equal(0);
    expect(await dao.netVotes(0)).to.equal(0);
    expect(await dao.totalVotes(0)).to.equal(0);
    expect(await dao.voteRecord(0, deployer.address)).to.equal(10);
  });

  it("shouldn't let you withdraw completed proposals", async () => {
    await expect(
      dao.withdrawProposal(0)
    ).to.be.revertedWith(`InactiveProposal(0)`);
  });

  it("shouldn't queue proposals with insufficient participation", impermanent(async () => {
    await expect(
      await dao.propose(TYPE, false, INFO)
    ).to.emit(dao, "Proposal").withArgs(2, TYPE, deployer.address, false, INFO);
    await dao.vote([2], [1]);
    await increaseTime(parseInt(await dao.votingPeriod()));
    await expect(dao.queueProposal(2)).to.be.revertedWith("NotEnoughParticipation(2, 1, 10)");
  }));
});
