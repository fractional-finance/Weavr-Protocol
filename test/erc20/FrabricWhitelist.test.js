const { ethers, waffle } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { increaseTime } = require("../common.js");

let signers, deployer, others;
let parent, whitelist;

const oldInfo = "0x1111111111111111111111111111111111111111111111111111111111111111";
const newInfo = "0x2222222222222222222222222222222222222222222222222222222222222222";

describe("FrabricWhitelist", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    deployer = signers.splice(0, 1);
    others = signers.splice(0, 3);

    FrabricWhitelist = await ethers.getContractFactory("TestFrabricWhitelist");
    parent = await FrabricWhitelist.deploy(ethers.constants.AddressZero);
    whitelist = await FrabricWhitelist.deploy(parent.address);

    // Verify it emitted ParentChange on initialization
    let change = (await parent.queryFilter(parent.filters.ParentChange()))[0].args;
    expect(change.oldParent).to.equal(ethers.constants.AddressZero);
    expect(change.newParent).to.equal(ethers.constants.AddressZero);
    change = (await whitelist.queryFilter(whitelist.filters.ParentChange()))[0].args;
    expect(change.oldParent).to.equal(ethers.constants.AddressZero);
    expect(change.newParent).to.equal(parent.address);
    expect(await whitelist.parent()).to.equal(parent.address);
  });

  it("should require any parent implements IWhitelist", async () => {
    let random = await (await ethers.getContractFactory("TestERC20")).deploy("Name", "SYM");
    await expect(
      whitelist.setParent(random.address)
    ).to.be.revertedWith(`UnsupportedInterface("${random.address}", "0xd936547e")`);
  });

  it("should let you set a parent", async () => {
    // This is already tested thanks to the before function
    await expect(
      await whitelist.setParent(parent.address)
    ).to.emit(whitelist, "ParentChange").withArgs(parent.address, parent.address);
    expect(await whitelist.parent()).to.equal(parent.address);
  });

  it("should track whitelisted and info hashes", async () => {
    const tx = await whitelist.setWhitelisted(others[0].address, oldInfo);
    await expect(tx).to.emit(whitelist, "Whitelisted").withArgs(others[0].address, true);
    await expect(tx).to.emit(whitelist, "InfoChange").withArgs(others[0].address, ethers.constants.HashZero, oldInfo);
    expect(await whitelist.info(others[0].address)).to.equal(oldInfo);
    assert(await whitelist.explicitlyWhitelisted(others[0].address));
    assert(await whitelist.whitelisted(others[0].address));
    expect(await whitelist.removed(others[0].address)).to.equal(false);
  });

  it("should support updating info hashes", async () => {
    const tx = await whitelist.setWhitelisted(others[0].address, newInfo);
    await expect(tx).to.not.emit(whitelist, "Whitelisted");
    await expect(tx).to.emit(whitelist, "InfoChange").withArgs(others[0].address, oldInfo, newInfo);
    expect(await whitelist.info(others[0].address)).to.equal(newInfo);
  });

  it("should handle removals", async () => {
    await expect(
      await whitelist.remove(others[0].address)
    ).to.emit(whitelist, "Whitelisted").withArgs(others[0].address, false);
    expect(await whitelist.explicitlyWhitelisted(others[0].address)).to.equal(false);
    expect(await whitelist.whitelisted(others[0].address)).to.equal(false);
    assert(await whitelist.removed(others[0].address));
  });

  it("should support parent whitelisting", async () => {
    await parent.setWhitelisted(others[1].address, newInfo);
    assert(await whitelist.whitelisted(others[1].address));
    expect(await whitelist.explicitlyWhitelisted(others[1].address)).to.equal(false);
  });

  it("should considered removed even if parent whitelisted", async () => {
    await parent.setWhitelisted(others[0].address, newInfo);
    expect(await whitelist.whitelisted(others[0].address)).to.equal(false);
  })

  it("should support going global", async () => {
    expect(await whitelist.setGlobal()).to.emit(whitelist, "GlobalAcceptance");
    assert(await whitelist.global());
    assert(await whitelist.whitelisted(others[2].address));
  });
});
