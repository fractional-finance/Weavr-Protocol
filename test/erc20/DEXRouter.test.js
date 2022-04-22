const { ethers } = require("hardhat");
const { expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");
const { OrderType } = require("../common.js");

let deployer;
let usd, frbc, router;

describe("DEXRouter", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    deployer = signers.splice(0, 1)[0];

    usd = await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD");
    ({ frbc } = await FrabricERC20.deployFRBC(usd.address));
    await frbc.mint(deployer.address, ethers.utils.parseUnits("1"));
    router = (await (await ethers.getContractFactory("DEXRouter")).deploy());
  });

  it("should be able to place buy orders", async () => {
    await usd.approve(router.address, ethers.constants.MaxUint256);
    let tx = await router.buy(frbc.address, usd.address, 2, 2, 1);
    await expect(tx).to.emit(usd, "Transfer").withArgs(deployer.address, frbc.address, 2);
    await expect(tx).to.emit(frbc, "NewOrder").withArgs(OrderType.Buy, 2);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(deployer.address, 2, 1);
  });

  it("should use the msg.sender as the trader", async () => {
    expect(await frbc.getOrderTrader(2, 0)).to.equal(deployer.address);
  });
});
