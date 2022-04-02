const { ethers } = require("hardhat");
const { expect } = require("chai");
const FrabricERC20 = require("../scripts/deployFrabricERC20.js");
const Crowdfund = require("../scripts/deployCrowdfundProxy.js");
const ThreadDeployer = require("../scripts/deployThreadDeployer.js");



describe("Crowdfund Positive Test Cases", async  () => {
  let crowdfund;
  let target;
  let erc20Beacon;
  
  let signer;
  let otherUser;

  let threadDeployer;
  let auction = {
    address: "0x0000000000000000000000000000000000000000"
  };

  before(async () => {
    
    const Erc20 = await ethers.getContractFactory("TestERC20");
    erc20 = await Erc20.deploy("Test", "T");
    await erc20.deployed();

    erc20Beacon = await FrabricERC20.deployBeacon();
    threadDeployer = await ThreadDeployer(erc20Beacon.address, auction.address);

    [signer, otherUser] = await ethers.getSigners();

    target = ethers.BigNumber.from("1000").toString();
    const ABIC = ethers.utils.defaultAbiCoder;
    const data = ABIC.encode(
      ["address", "uint256"],
      [erc20.address, target]
    );
    
    const TestFrabric = await ethers.getContractFactory("TestFrabric");
    const testFrabric = await TestFrabric.deploy();
    await testFrabric.deployed();
    await testFrabric.setWhitelisted(otherUser.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await testFrabric.setWhitelisted(signer.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    
    console.log(await threadDeployer.threadDeployer.owner());
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

  });
  describe("Test until finsish+burn", async () => {
    it("Should launch a crowdfund with a non-zero fundraising target", async () => {
      expect(threadDeployer.threadDeployer).to.emit(Crowdfund, "CrowdfundStarted");
      expect(threadDeployer.threadDeployer).to.emit(Crowdfund, "StateChange");
    });
    it("Should deposit tokens as a new backer", async () => {    
  
      const balance = await erc20.balanceOf(signer.address);
      const amount = ethers.BigNumber.from("100");
      await erc20.approve(crowdfund.address, balance);
      const tx = await crowdfund.deposit(amount);
      expect(tx).to.emit(Crowdfund, "Deposit");
      console.log((await crowdfund.deposited()).toNumber());
  
    });
    it("Should withdraw tokens as an existing backer", async () => {
      
      const amount = ethers.BigNumber.from("100");
      const tx = await crowdfund.withdraw(amount);
      expect(tx).to.emit(Crowdfund, "Withdraw");
      console.log((await crowdfund.deposited()).toNumber());
  
    });
    it("Should trigger executing status if crowdfunding target was reached, and was previously active", async () => {
  
      const amount = ethers.BigNumber.from(target);
      await crowdfund.deposit(amount);
      console.log((await crowdfund.deposited()).toNumber());
      const tx = await crowdfund.execute();
      expect(tx).to.emit(Crowdfund, "StateChange");
  
    });
    it("Should allow agent to trigger finished status if was previously executing", async () => {
      
      const tx = await crowdfund.finish();
      expect(tx).to.emit(Crowdfund, "StateChange");
  
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
    });
    it("Should allow agent to trigger refunding status if was previously executing", async () => {
    
      const amount = ethers.BigNumber.from(target);
      const tx = await crowdfund.refund(amount);
      expect(tx).to.emit(Crowdfund, "StateChange");
  
    });
    it("Should allow backers to claim their funds if the crowdfund status is refunding, and burn their crowdfund ERC20 tokens", async () => {
  
      const amount = ethers.BigNumber.from(target);
      const tx = await crowdfund.refund(signer.address);
      expect(tx).to.emit(Crowdfund, "Refund");
  
    });
    it("Should transfer total balance to agent when state changes to executing status", async () => {
      
      const agentBalance = await crowdfund.balanceOf(signer.address);
      expect(agentBalance.toNumber()).to.equal(target);
  
    });
  });
  
  
  
});

// describe("Crowdfund Negative Test Cases", accounts => {
//   let crowdfund;
//   beforeEach(async function () {
//     crowdfund =  await ethers.getContractFactory("Crowdfund");
//   });
    
//     it("Should not be allowed to back a crowdfund that has ended", async () => {});
//     it("Should not be allowed to withdraw funds from a crowdfund that is executing", async () => {});
//     it("Should not be allowed to withdraw funds from a crowdfund that has ended", async () => {});
//     it("Should not launch a crowdfund with a zero fundraising target", async () => {
//       // let crowdfund =  await ethers.getContractFactory("ERC20");
//     });
// });
