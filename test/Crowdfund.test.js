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
let erc20;
let data;
let agent;
let user1;
let user2;
let user3;
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

  let erc20Beacon = await FrabricERC20.deployBeacon();
  threadDeployer = await ThreadDeployer(erc20Beacon.address, auction.address);

  [agent, user1, user2, user3] = await ethers.getSigners();

  target = ethers.BigNumber.from("1000").toString();
  const ABIC = ethers.utils.defaultAbiCoder;
  data = ABIC.encode(
    ["address", "uint256"],
    [erc20.address, target]
  );
  
  const TestFrabric = await ethers.getContractFactory("TestFrabric");
  testFrabric = await TestFrabric.deploy();
  await testFrabric.deployed();
  await testFrabric.setWhitelisted(user1.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
  await testFrabric.setWhitelisted(user2.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
  await testFrabric.setWhitelisted(user3.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
  await testFrabric.setWhitelisted(agent.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
  
  await threadDeployer.threadDeployer.transferOwnership(testFrabric.address);
  
  const res = await testFrabric.threadDeployDeployer(
    threadDeployer.threadDeployer.address,
    0,
    agent.address,
    "TestThread",
    "TT",
    data
  );
  const add = (await threadDeployer.threadDeployer.queryFilter(threadDeployer.threadDeployer.filters.Thread()))[0].args.crowdfund;
  const Crowdfund = await ethers.getContractFactory("Crowdfund");
  crowdfund = Crowdfund.attach(add);
}

describe("Happy Path", async  () => {
  
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
  
      const balance = {
        agent: await erc20.balanceOf(agent.address),
        user1: await erc20.balanceOf(user1.address),
      }
      const amount = ethers.BigNumber.from("100");
      
      await erc20.approve(crowdfund.address, balance.agent);
      await erc20.transfer(user1.address, amount);
      await erc20.connect(user1).approve(crowdfund.address, balance.agent);
      const tx = await crowdfund.connect(user1).deposit(amount);
      expect(tx).to.emit(Crowdfund, "Deposit");

      const event = (await crowdfund.queryFilter(crowdfund.filters.Deposit()));
      expect(event[0].args.amount).to.equal(amount);

    });
    it("Should withdraw tokens as an existing backer", async () => {
      
      const amount = ethers.BigNumber.from("100");
      const tx = await crowdfund.connect(user1).withdraw(amount);
      
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
      
      const agentBalance = await crowdfund.balanceOf(agent.address);
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
  
      const depositor = agent.address;
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
      
      const balance = await erc20.balanceOf(agent.address);
      const amount = ethers.BigNumber.from(target);
      
      await erc20.approve(crowdfund.address, balance);
      await erc20.connect(user1).approve(crowdfund.address, balance);
      await erc20.transfer(user1.address, amount);
      const tx = await crowdfund.connect(user1).deposit(amount);
      
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
      const dist = (await crowdfund.queryFilter(crowdfund.filters.Distributed()));
      console.log(await crowdfund.connect(user1).balanceOf(user1.address));
      const ID = (dist[0].args.id);
      console.log(dist[0].args.amount);
      const tx = await crowdfund.connect(user1).claim(user1.address, ID);
      expect(tx).emit(Crowdfund, "Claimed");
    
    });
    
  });
  
  
  
});

describe("Crowdfund Negative Test Cases", accounts => {
  beforeEach(async function () {
   await init();
   stateCounter = 0;
  });
    
  it("Should not be allowed to back a crowdfund that has ended", async () => {
    const balance = await erc20.balanceOf(agent.address);
    const amount = ethers.BigNumber.from(target);
    
    await erc20.approve(crowdfund.address, balance);
    
    const tx = await crowdfund.deposit(amount);
    
    const tx1 = await crowdfund.execute();
    expect(tx1).to.emit(Crowdfund, "StateChange");
    stateCounter++;
    const tx2 = await crowdfund.finish();
    expect(tx2).to.emit(Crowdfund, "StateChange");
    stateCounter++;
    const event = (await crowdfund.queryFilter(crowdfund.filters.StateChange()));
    expect(event[stateCounter].args.state).to.equal(State.Finished);
    // const tx3 = await crowdfund.deposit(amount);
    expect(
      await crowdfund.deposit(amount)
    )
    .to.be.revertedWith(
      "'InvalidState(3, 0)'"
    );
  });
  it("Should not be allowed to withdraw funds from a crowdfund that is executing", async () => {});
  it("Should not be allowed to withdraw funds from a crowdfund that has ended", async () => {});
  it("Should not launch a crowdfund with a zero fundraising target", async () => {
    // let crowdfund =  await ethers.getContractFactory("ERC20");
  });
});
