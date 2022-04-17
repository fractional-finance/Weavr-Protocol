const { ethers } = require("hardhat");
const { expect } = require("chai");
const FrabricERC20 = require("../scripts/deployFrabricERC20.js");
const Thread = require("../scripts/deployThread.js");
const ThreadDeployer = require("../scripts/deployThreadDeployer.js");

let thread;
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
let ipfsTag ="0x" + (new Buffer("ipfs").toString("hex")).repeat(8);

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

  await testFrabric.setGovernor(agent.address, 2);



  const res = await testFrabric.threadDeployDeployer(
      threadDeployer.threadDeployer.address,
      0,
      agent.address,
      ipfsTag,
      "TestThread",
      "TT",
      data
  );
  const add = (await threadDeployer.threadDeployer.queryFilter(threadDeployer.threadDeployer.filters.Thread()))[0].args.thread;
  let thread = Thread.deployTestThread(agent)
}

describe("Thread Happy-Path", async () => {
  before(async () => {
    await init();
  });
  it("Should initialize a Thread changing emitting AgentChanged and FrabricChanged", async () => {
    expect(threadDeployer.threadDeployer).to.emit(Thread, "AgentChanged");
    expect(threadDeployer.threadDeployer).to.emit(Thread, "FrabricChanged");

  });

});
  // it("should mint tokens to test with", async () => {
  // });

  // it("should support placing sell orders", async () => {
  // });

  // it("should support placing multiple buy orders", async () => {
  // });

  // it("should support fully filling sell order", async () => {
  // });

  // it("should support partially filled sell orders", async () => {
  // });

  // it("should support placing multiple new sell orders", async () => {
  // });

  // it("should support placing partially filling buy orders from sell", async () => {
  // });

  // it("should support sell/buy pair across multiple account", async () => {
  // });


// contract("IntegratedLimitOrderDex", (accounts) => {
//   let dex;
//   beforeEach(async () => {
//     dex = await StubbedDex.new();
//     (await dex.totalSupply.call()).should.be.eq.BN(await dex.balanceOf.call(accounts[0]));
//     (await dex.totalSupply.call()).toString().should.be.equal("1000000000000000000");
//     await dex.approve(dex.address, await dex.totalSupply.call());
//   });

//   it("should prevent cheating when buying", async () => {
//     try {
//       const price = web3.utils.toBN(web3.utils.toWei("1"));
//       await dex.buy(1, price, {value: price.div(web3.utils.toBN(2))});
//       assert.fail("should prevent cheating when value is not equal to amount purchased")
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Invalid message value"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent cheating when selling", async () => {
//     try {
//       const price = web3.utils.toBN(web3.utils.toWei("1"));
//       await dex.sell(1, price, {from: accounts[1]});
//       assert.fail("should prevent cheating when value is not equal to amount purchased")
//     } catch(err) {
//       const expectedError = "ERC20: transfer amount exceeds balance"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent overpaying when buying", async () => {
//     try {
//       const price = web3.utils.toBN(web3.utils.toWei("1"));
//       await dex.buy(1, price, {value: price.mul(web3.utils.toBN(2))});
//       assert.fail("should prevent overpaying when value is not equal to amount purchased")
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Invalid message value"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent 0 buy price", async () => {
//     try {
//       const price = web3.utils.toWei("0.5")
//       await dex.buy(1, 0, {value: 2 * price});
//       assert.fail("should prevent 0 buy price");
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Price is 0"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent 0 buy amount", async () => {
//     try {
//       const price = web3.utils.toWei("0.5")
//       await dex.buy(0, price, {value: 2 * price});
//       assert.fail("should prevent 0 buy amount");
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Amount is 0"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent 0 sell price", async () => {
//     try {
//       await dex.sell(1, 0);
//       assert.fail("should prevent 0 buy price");
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Price is 0"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });

//   it("should prevent 0 sell amount", async () => {
//     try {
//       const price = web3.utils.toWei("0.5")
//       await dex.buy(0, price);
//       assert.fail("should prevent 0 buy amount");
//     } catch(err) {
//       const expectedError = "IntegratedLimitOrderDex: Amount is 0"
//       const actualError = err.reason;
//       assert.equal(actualError, expectedError, "should not be permitted")
//     }
//   });
// });
