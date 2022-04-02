const { ethers } = require("hardhat");
const { expect } = require("chai");
const FrabricERC20 = require("../scripts/deployFrabricERC20.js");
const Crowdfund = require("../scripts/deployCrowdfundProxy.js");
const Beacon = require("../scripts/deployBeacon.js");
const ThreadDeployer = require("../scripts/deployThreadDeployer.js");



describe("Crowdfund Positive Test Cases", async  () => {
  let crowdfund;
  let target;
  let erc20Beacon;
  
  let whitelist;
  let signer;
  let otherUser;

  let threadDeployerProxy
  let crowdfundProxy;
  let threadBeacon;
  let threadDeployer;
  let auction = {
    address: "0x0000000000000000000000000000000000000000"
  };

  beforeEach(async () => {
    
    const Erc20 = await ethers.getContractFactory("TestERC20");
    erc20 = await Erc20.deploy("Test", "T");
    await erc20.deployed();

    erc20Beacon = await FrabricERC20.deployBeacon();
    threadDeployer = await ThreadDeployer(erc20Beacon.address, auction.address);

    [signer, otherUser] = await ethers.getSigners();

    const Whitelist = await ethers.getContractFactory("TestWhitelist");
    whitelist = await Whitelist.deploy();
    await whitelist.deployed();
    await whitelist.whitelist(signer.address);
    await whitelist.whitelist(otherUser.address);

    target = ethers.BigNumber.from("1000").toString();
    const ABIC = ethers.utils.defaultAbiCoder;
    const data = ABIC.encode(
      ["address", "uint256"],
      [erc20.address, target]
    );
    
    const TestFrabric = await ethers.getContractFactory("TestFrabric");
    const testFrabric = await TestFrabric.deploy();
    await testFrabric.deployed();
    console.log(await threadDeployer.threadDeployer.owner());
    await threadDeployer.threadDeployer.transferOwnership(testFrabric.address);
    const funkySigner = await ethers.providers.jsonRpcProvider.connectUnchecked();
    // console.log(testFrabric.address);
    // console.log(await threadDeployer.threadDeployer.owner());
    // console.log(testFrabric.signer);
    await threadDeployer.threadDeployer.connect(funkySigner).deploy(
      0,
      signer.address,
      "TestThread",
      "TT",
      data
    );
    // const res = await threadDeployer.threadDeployer.deploy(
    //   0,
    //   signer.address,
    //   "TestThread",
    //   "TT",
    //   data
    // );
    // crowdfund = res;
  });
  it("Should launch a crowdfund with a non-zero fundraising target", async () => {
    expect(crowdfundProxy).to.emit(Crowdfund, "CrowdfundStarted");
    expect(crowdfundProxy).to.emit(Crowdfund, "StateChange");
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
  it("Should allow agent to trigger refunding status if was previously executing", async () => {
    
    const amount = ethers.BigNumber.from(target);
    const tx = await crowdfund.refund(amount);
    expect(tx).to.emit(Crowdfund, "StateChange");

  });
  it("Should allow backers to claim their funds if the crowdfund status is refunding, and burn their crowdfund ERC20 tokens", async () => {

    const amount = ethers.BigNumber.from(target);
    const tx = await crowdfund.claimRefund(signer.address);
    expect(tx).to.emit(Crowdfund, "Refund");

  });
  it("Should transfer total balance to agent when state changes to executing status", async () => {
    
    const agentBalance = await crowdfund.balanceOf(signer.address);
    expect(agentBalance.toNumber()).to.equal(target);

  });
  it("Should allow agent to trigger finished status if was previously executing", async () => {
    
    console.log(crowdfund.state)
    const tx = await crowdfund.finish();
    expect(tx).to.emit(Crowdfund, "StateChange");

  });
  it("Should burn backer crowdfund tokens when state changes to finished status", async () => {

    const depositor = signer.address;
    console.log(await crowdfund.balanceOf(depositor));
    const tx = await crowdfund.burn(depositor);
    // expect(await crowdfund.balanceOf(depositor)).to.equal(0);
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
