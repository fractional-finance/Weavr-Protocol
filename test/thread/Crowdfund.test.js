const { ethers, waffle } = require("hardhat");
const { expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");
const deployCrowdfundProxy = require("../../scripts/deployCrowdfundProxy.js");
const deployThreadDeployer = require("../../scripts/deployThreadDeployer.js");

const common = require("../common.js");

const State = {
  Active: 0,
  Executing: 1,
  Refunding: 2,
  Finished: 3
}

let signers, deployer, governor, participant, other;
let erc20;
let ferc20, crowdfund;

describe("Crowdfund", async () => {
  before(async () => {
    // Deploy the test Frabric
    const TestFrabric = await ethers.getContractFactory("TestFrabric");
    const frabric = await TestFrabric.deploy();

    // Add the governor and whitelist the participants
    signers = await ethers.getSigners();
    [ deployer, governor, participant, other ] = signers.splice(0, 4);
    await frabric.whitelist(governor.address);
    await frabric.setGovernor(governor.address, common.GovernorStatus.Active);
    await frabric.whitelist(participant.address);
    await frabric.whitelist(other.address);

    // Deploy the ThreadDeployer
    const erc20Beacon = await FrabricERC20.deployBeacon();
    const { threadDeployer } = await deployThreadDeployer(erc20Beacon.address, ethers.constants.AddressZero);
    await threadDeployer.transferOwnership(frabric.address);

    // Have the ThreadDeployer deploy everything
    const ERC20 = await ethers.getContractFactory("TestERC20");
    // TODO: Test with an ERC20 which uses 6 decimals
    erc20 = await ERC20.deploy("Test Token", "TEST");
    const tx = await frabric.deployThread(
      threadDeployer.address,
      0,
      "Test Thread",
      "THREAD",
      ethers.utils.id("ipfs"),
      governor.address,
      erc20.address,
      1000
    );

    // Get the ERC20/Crowdfund
    ferc20 = (await ethers.getContractFactory("FrabricERC20")).attach(
      (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.erc20
    );
    crowdfund = (await ethers.getContractFactory("Crowdfund")).attach(
      (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()))[0].args.crowdfund
    ).connect(participant);

    // Do basic tests it emits the expected events at setup
    expect(await crowdfund.contractName()).to.equal(ethers.utils.id("Crowdfund"));
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Active);
    expect(await crowdfund.state()).to.equal(State.Active);
  });

  it("should allow depositing", async () => {
    await erc20.transfer(participant.address, 100);
    await erc20.connect(participant).approve(crowdfund.address, 100);
    const tx = await crowdfund.deposit(100);
    await expect(tx).to.emit(erc20, "Transfer").withArgs(participant.address, crowdfund.address, 100);
    await expect(tx).to.emit(crowdfund, "Deposit").withArgs(participant.address, 100);
    expect(await erc20.balanceOf(participant.address)).to.equal(0);
    expect(await erc20.balanceOf(crowdfund.address)).to.equal(100);
  });

  it("shouldn't allow people who aren't whitelisted to participate", async () => {
    await expect(
      crowdfund.connect(signers[0]).deposit(1)
    ).to.be.revertedWith(`NotWhitelisted("${signers[0].address}")`);
  });

  it("should allow withdrawing", async () => {
    const tx = await crowdfund.withdraw(20);
    await expect(tx).to.emit(erc20, "Transfer").withArgs(crowdfund.address, participant.address, 20);
    await expect(tx).to.emit(crowdfund, "Withdraw").withArgs(participant.address, 20);
    expect(await erc20.balanceOf(participant.address)).to.equal(20);
    expect(await erc20.balanceOf(crowdfund.address)).to.equal(80);
  });

  it("shouldn't allow anyone to cancel", async () => {
    await expect(
      crowdfund.cancel()
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${governor.address}")`);
  });

  it("should allow cancelling", async () => {
    snapshot = await common.snapshot();
    const balance = await erc20.balanceOf(crowdfund.address);
    const tx = await crowdfund.connect(governor).cancel();
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Refunding);
    await expect(tx).to.emit(crowdfund, "Distribution").withArgs(0, erc20.address, balance);
    expect(await crowdfund.state()).to.equal(State.Refunding);
  });

  // Does not test claiming refunds as that's routed through DistributionERC20

  it("shouldn't allow depositing when cancelled", async () => {
    await expect(
      crowdfund.deposit(1)
    ).to.be.revertedWith("InvalidState(2, 0)");

    // Revert to the next snapshot for the rest of the tests
    await common.revert(snapshot);
  });

  // Less of a test and more transiting the state to where it needs to be for testing
  it("should reach target", async () => {
    const amount = 1000 - parseInt(await erc20.balanceOf(crowdfund.address));
    await erc20.transfer(other.address, amount);
    await erc20.connect(other).approve(crowdfund.address, amount);
    await expect(
      await crowdfund.connect(other).deposit(amount)
    ).to.emit(crowdfund, "Deposit").withArgs(other.address, amount);
  });

  // TODO also test over depositing from target normalizes to amount needed

  it("shouldn't allow depositing more than the target", async () => {
    // TODO
  });

  it("should only allow the governor to execute", async () => {
    await expect(
      crowdfund.execute()
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${governor.address}")`);
  });

  it("should allow executing once it reaches target", async () => {
    const tx = await crowdfund.connect(governor).execute();
    await expect(tx).to.emit(erc20, "Transfer").withArgs(crowdfund.address, governor.address, 1000);
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Executing);
    await expect(await crowdfund.state()).to.equal(State.Executing);
    expect(await erc20.balanceOf(governor.address)).to.equal(1000);
    expect(await erc20.balanceOf(crowdfund.address)).to.equal(0);
  });

  it("shouldn't allow depositing when executing", async () => {
    await expect(
      crowdfund.deposit(1)
    ).to.be.revertedWith("InvalidState(1, 0)");
  });

  it("should allow finishing", async () => {
    // Create a snapshot to use to test refunds with
    snapshot = await common.snapshot();

    await expect(
      await crowdfund.connect(governor).finish()
    ).to.emit(crowdfund, "StateChange").withArgs(State.Finished);
    expect(await crowdfund.state()).to.equal(State.Finished);
  });

  it("shouldn't allow depositing when finished", async () => {
    await expect(
      crowdfund.deposit(1)
    ).to.be.revertedWith("InvalidState(3, 0)");
  });

  it("should allow claiming Thread tokens", async () => {
    const balance = await crowdfund.balanceOf(participant.address);
    await crowdfund.burn(participant.address);
    expect(await crowdfund.balanceOf(participant.address)).to.equal(0);
    expect(await ferc20.balanceOf(participant.address)).to.equal(balance);
  });

  it("should only allow the governor to refund", async () => {
    common.revert(snapshot);

    await expect(
      crowdfund.refund(0)
    ).to.be.revertedWith(`NotGovernor("${participant.address}", "${governor.address}")`);
  });

  it("should allow refunding", async () => {
    await erc20.connect(governor).approve(crowdfund.address, 900);
    const tx = await crowdfund.connect(governor).refund(900);
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Refunding);
    await expect(tx).to.emit(erc20, "Transfer").withArgs(governor.address, crowdfund.address, 900);
    await expect(tx).to.emit(crowdfund, "Distribution").withArgs(0, erc20.address, 900);
    expect(await crowdfund.state()).to.equal(State.Refunding);
  });

  // Does not test depositing when refunding as cancelled and refunding have the
  // same state, where the former is already tested

  // Does not test claiming refunds as that's routed through DistributionERC20
});
