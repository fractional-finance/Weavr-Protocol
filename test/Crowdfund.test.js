const { ethers } = require("hardhat");
const { expect } = require("chai");
const FrabricERC20 = require("../scripts/deployFrabricERC20.js");
const Crowdfund = require("../scripts/deployCrowdfundProxy.js");
const ThreadDeployer = require("../scripts/deployThreadDeployer.js");

const State = {
  Active: 0,
  Executing: 1,
  Refunding: 2,
  Finished: 3
}

let crowdfund;
  let target;
  let erc20Beacon;
  let data;
  let signer;
  let otherUser;
  let testFrabric;
  let threadDeployer;
  let auction = {
    address: "0x0000000000000000000000000000000000000000"
  };

  let stateCounter;

  async function init(){
    const Erc20 = await ethers.getContractFactory("TestERC20");
    erc20 = await Erc20.deploy("Test", "T");
    await erc20.deployed();

    erc20Beacon = await FrabricERC20.deployBeacon();
    threadDeployer = await ThreadDeployer(erc20Beacon.address, auction.address);

    [signer, otherUser] = await ethers.getSigners();

    target = ethers.BigNumber.from("1000").toString();
    const ABIC = ethers.utils.defaultAbiCoder;
    data = ABIC.encode(
      ["address", "uint256"],
      [erc20.address, target]
    );
    
    const TestFrabric = await ethers.getContractFactory("TestFrabric");
    testFrabric = await TestFrabric.deploy();
    await testFrabric.deployed();
    await testFrabric.setWhitelisted(otherUser.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await testFrabric.setWhitelisted(signer.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    
    await threadDeployer.threadDeployer.transferOwnership(testFrabric.address);
    
    const res = await testFrabric.threadDeployDeployer(
      threadDeployer.threadDeployer.address,
      0,
      signer.address,
      "TestThread",
      "TT",
      data
    );
    const add = (await threadDeployer.threadDeployer.queryFilter(threadDeployer.threadDeployer.filters.Thread()))[0].args.crowdfund;
    const Crowdfund = await ethers.getContractFactory("Crowdfund");
    crowdfund = Crowdfund.attach(add);
  }

describe("Crowdfund Positive Test Cases", async  () => {
  
  describe("Test until finsish+burn", async () => {
    before(async () => {
      stateCounter = -1;
      await init();
    });
    it("Should launch a crowdfund with a non-zero fundraising target", async () => {
    
      expect(threadDeployer.threadDeployer).to.emit(Crowdfund, "CrowdfundStarted");
      expect(threadDeployer.threadDeployer).to.emit(Crowdfund, "StateChange");
      stateCounter++;

    });
    it("Should deposit tokens as a new backer", async () => {    
  
      const balance = await erc20.balanceOf(signer.address);
      const amount = ethers.BigNumber.from("100");
      
      await erc20.approve(crowdfund.address, balance);
      
      const tx = await crowdfund.deposit(amount);
      expect(tx).to.emit(Crowdfund, "Deposit");

      const event = (await crowdfund.queryFilter(crowdfund.filters.Deposit()));
      expect(event[0].args.amount).to.equal(amount);

    });
    it("Should withdraw tokens as an existing backer", async () => {
      
      const amount = ethers.BigNumber.from("100");
      const tx = await crowdfund.withdraw(amount);
      
      expect(tx).to.emit(Crowdfund, "Withdraw");
      
      const event = (await crowdfund.queryFilter(crowdfund.filters.Withdraw()));
      expect(event[0].args.amount).to.equal(amount);

  
    });
    it("Should trigger executing status if crowdfunding target was reached, and was previously active", async () => {
  
      const amount = ethers.BigNumber.from(target);
      
      await crowdfund.deposit(amount);
      
      const tx = await crowdfund.execute();
      expect(tx).to.emit(Crowdfund, "StateChange");
      stateCounter++;
      const event = (await crowdfund.queryFilter(crowdfund.filters.StateChange()));
      expect(event[stateCounter].args.state).to.equal(State.Executing);
    });
    it("Should transfer total balance to agent when state changes to executing status", async () => {
      
      const agentBalance = await crowdfund.balanceOf(signer.address);
      expect(agentBalance).to.equal(target);
  
    });
    it("Should allow agent to trigger finished status if was previously executing", async () => {
      
      const tx = await crowdfund.finish();
      expect(tx).to.emit(Crowdfund, "StateChange");
      stateCounter++;
      const event = (await crowdfund.queryFilter(crowdfund.filters.StateChange()));
      expect(event[stateCounter].args.state).to.equal(State.Finished);
  
    });
    it("Should burn backer crowdfund tokens when state changes to finished status", async () => {
  
      const depositor = signer.address;
      const balance = await crowdfund.balanceOf(depositor);
      const tx = await crowdfund.burn(depositor);
      expect(await crowdfund.balanceOf(depositor)).to.equal(0);

      const add = (await threadDeployer.threadDeployer.queryFilter(threadDeployer.threadDeployer.filters.Thread()))[0].args.erc20;
      
      const ERC20 = await ethers.getContractFactory("FrabricERC20");
      ferc20 = ERC20.attach(add);
      expect(await ferc20.balanceOf(depositor)).to.equal(balance);


    });
  
  });
  describe("Implementation to refound a Crowdfund", async () => {
    before(async () => {

      await init();
     
      
      stateCounter = 0;
    });
    it("Should allow agent to trigger refunding status if was previously executing", async () => {
      const balance = await erc20.balanceOf(signer.address);
      const amount = ethers.BigNumber.from(target);
      
      await erc20.approve(crowdfund.address, balance);
      
      const tx = await crowdfund.deposit(amount);
      
      const tx1 = await crowdfund.execute();
      expect(tx1).to.emit(Crowdfund, "StateChange");
      stateCounter++;
      const tx2 = await crowdfund.refund(amount);
      expect(tx2).to.emit(Crowdfund, "StateChange");
      stateCounter++;
      expect(tx).to.emit(Crowdfund, "Distributed");
      const state = (await crowdfund.queryFilter(crowdfund.filters.Distributed()));
      
      expect(state[0].args.amount).to.equal(amount);
    });
    it("Should allow backers to claim their funds if the crowdfund status is refunding, and burn their crowdfund ERC20 tokens", async () => {
      const event = (await crowdfund.queryFilter(crowdfund.filters.StateChange()));
      expect(event[stateCounter].args.state).to.equal(State.Refunding);
    });
    
  });
  
  
  
});

describe("Crowdfund Negative Test Cases", accounts => {
  let crowdfund;
  before(async function () {
   await init();
  });
    
    it("Should not be allowed to back a crowdfund that has ended", async () => {});
    it("Should not be allowed to withdraw funds from a crowdfund that is executing", async () => {});
    it("Should not be allowed to withdraw funds from a crowdfund that has ended", async () => {});
    it("Should not launch a crowdfund with a zero fundraising target", async () => {
      // let crowdfund =  await ethers.getContractFactory("ERC20");
    });
});
