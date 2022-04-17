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

let signers, deployer, governor;
let erc20, target;
let ferc20, crowdfund;

describe("Crowdfund", async () => {
  before(async () => {
    // Deploy the test Frabric
    const TestFrabric = await ethers.getContractFactory("TestFrabric");
    const frabric = await TestFrabric.deploy();

    // Add the governor and whitelist the signers
    signers = await ethers.getSigners();
    [ deployer, governor ] = signers.splice(0, 2);
    await frabric.setWhitelisted(governor.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frabric.setGovernor(governor.address, 2);
    for (let i = 0; i < 3; i++) {
      await frabric.setWhitelisted(signers[i].address, "0x0000000000000000000000000000000000000000000000000000000000000002");
    }

    // Deploy the ThreadDeployer
    const erc20Beacon = await FrabricERC20.deployBeacon();
    const { threadDeployer } = await deployThreadDeployer(erc20Beacon.address, ethers.constants.AddressZero);
    await threadDeployer.transferOwnership(frabric.address);

    // Have the ThreadDeployer deploy everything
    const ERC20 = await ethers.getContractFactory("TestERC20");
    // TODO: Test with an ERC20 which uses
    erc20 = await ERC20.deploy("Test Token", "TEST");
    target = ethers.BigNumber.from("1000");
    const tx = await frabric.deployThread(
      threadDeployer.address,
      0,
      "Test Thread",
      "THREAD",
      "0x" + (new Buffer.from("ipfs").toString("hex")).repeat(8),
      governor.address,
      erc20.address,
      target
    );

    // Get the ERC20/Crowdfund
    ferc20 = (await ethers.getContractFactory("FrabricERC20")).attach(
      (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.erc20
    );
    crowdfund = (await ethers.getContractFactory("Crowdfund")).attach(
      (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()))[0].args.crowdfund
    );

    // Do basic tests it emits the expected events at setup
    // TODO: Make this complete
    await expect(tx).to.emit(crowdfund, "CrowdfundStarted")
    await expect(tx).to.emit(crowdfund, "StateChange");
  });

  it("should allow depositing", async () => {
    const amount = ethers.BigNumber.from("100");
    await erc20.transfer(signers[0].address, amount);
    await erc20.connect(signers[0]).approve(crowdfund.address, amount);
    await expect(
      await crowdfund.connect(signers[0]).deposit(amount)
    ).to.emit(crowdfund, "Deposit").withArgs(signers[0].address, amount);
    // TODO: Check balances
  });

  it("should allow withdrawing", async () => {
    const amount = ethers.BigNumber.from("20");
    await expect(
      await crowdfund.connect(signers[0]).withdraw(amount)
    ).to.emit(crowdfund, "Withdraw").withArgs(signers[0].address, amount);
    // TODO: Check balances
  });

  it("shouldn't allow anyone to cancel", async () => {
    // TODO
  });

  it("should allow cancelling", async () => {
    snapshot = await common.snapshot();
    const balance = await erc20.balanceOf(crowdfund.address);
    const tx = await crowdfund.connect(governor).cancel();
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Refunding);
    await expect(tx).to.emit(crowdfund, "Distributed").withArgs(0, erc20.address, balance);
    // TODO: check state is actually updated
  });

  // Does not test claiming refunds as that's routed through DistributionERC20

  it("shouldn't allow depositing when cancelled", async () => {
    await expect(
      crowdfund.connect(signers[0]).deposit(target)
    ).to.be.revertedWith("InvalidState(2, 0)");

    // Revert to the next snapshot for the rest of the tests
    await common.revert(snapshot);
  });

  // Less of a test and more transiting the state to where it needs to be for testing
  it("should reach target", async () => {
    const amount = ethers.BigNumber.from(target).sub(await erc20.balanceOf(crowdfund.address));
    await erc20.transfer(signers[1].address, amount);
    await erc20.connect(signers[1]).approve(crowdfund.address, amount);
    await expect(
      await crowdfund.connect(signers[1]).deposit(amount)
    ).to.emit(crowdfund, "Deposit").withArgs(signers[1].address, amount);
  });

  // TODO also test over depositing from target normalizes to amount needed

  it("shouldn't allow depositing more than the target", async () => {
    // TODO
  });

  it("should only allow the governor to execute", async () => {
    // TODO
  });

  it("should allow executing once it reaches target", async () => {
    await expect(
      await crowdfund.connect(governor).execute()
    ).to.emit(crowdfund, "StateChange").withArgs(State.Executing);
    // TODO: actually check the state was changed

    expect(await erc20.balanceOf(governor.address)).to.equal(target);
    expect(await erc20.balanceOf(crowdfund.address)).to.equal(0);
  });

  it("shouldn't allow depositing when executing", async () => {
    await expect(
      crowdfund.connect(signers[0]).deposit(target)
    ).to.be.revertedWith("InvalidState(1, 0)");
  });

  it("should allow finishing", async () => {
    // Create a snapshot to use to test refunds with
    snapshot = await common.snapshot();

    await expect(
      await crowdfund.connect(governor).finish()
    ).to.emit(crowdfund, "StateChange").withArgs(State.Finished);
    // TODO: actually check the state was changed
  });

  it("shouldn't allow depositing when finished", async () => {
    // TODO
    await expect(
      crowdfund.connect(signers[0]).deposit(target)
    ).to.be.revertedWith("InvalidState(3, 0)");
  });

  it("should allow claiming Thread tokens", async () => {
    const balance = await crowdfund.balanceOf(signers[0].address);
    await crowdfund.burn(signers[0].address);
    expect(await crowdfund.balanceOf(signers[0].address)).to.equal(0);
    expect(await ferc20.balanceOf(signers[0].address)).to.equal(balance);
  });

  it("should only allow the governor to refund", async () => {
    common.revert(snapshot);

    // TODO
  });

  it("should allow refunding", async () => {
    await erc20.connect(governor).approve(crowdfund.address, target);
    const tx = await crowdfund.connect(governor).refund(target);
    await expect(tx).to.emit(crowdfund, "StateChange").withArgs(State.Refunding);
    await expect(tx).to.emit(crowdfund, "Distributed").withArgs(0, erc20.address, target);
  });

  // Does not test depositing when refunding as cancelled and refunding have the
  // same state, where the former is already tested

  // Does not test claiming refunds as that's routed through DistributionERC20
});
