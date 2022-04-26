const { ethers, waffle } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { WhitelistStatus } = require("../common.js");

let signers, deployer, person, parentPerson;
let parent, whitelist;

const oldInfo = "0x1111111111111111111111111111111111111111111111111111111111111111";
const newInfo = "0x2222222222222222222222222222222222222222222222222222222222222222";

describe("FrabricWhitelist", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    deployer = signers.splice(0, 1);
    [ person, parentPerson ] = signers.splice(0, 2);

    FrabricWhitelist = await ethers.getContractFactory("TestFrabricWhitelist");
    parent = await FrabricWhitelist.deploy(ethers.constants.AddressZero);
    whitelist = await FrabricWhitelist.deploy(parent.address);

    // Verify it emitted ParentChange on initialization
    let change = (await parent.queryFilter(parent.filters.ParentChange()))[0].args;
    expect(change.oldParent).to.equal(ethers.constants.AddressZero);
    expect(change.newParent).to.equal(ethers.constants.AddressZero);
    expect(await parent.parent()).to.equal(ethers.constants.AddressZero);

    change = (await whitelist.queryFilter(whitelist.filters.ParentChange()))[0].args;
    expect(change.oldParent).to.equal(ethers.constants.AddressZero);
    expect(change.newParent).to.equal(parent.address);
    expect(await whitelist.parent()).to.equal(parent.address);
  });

  it("should require any parent implements IFrabricWhitelistCore", async () => {
    const random = await (await ethers.getContractFactory("TestERC20")).deploy("Name", "SYM");
    await expect(
      whitelist.setParent(random.address)
    ).to.be.revertedWith(`UnsupportedInterface("${random.address}", "0x07bf0425")`);
  });

  it("should let you set a parent", async () => {
    // This is already tested thanks to before
    await expect(
      await whitelist.setParent(parent.address)
    ).to.emit(whitelist, "ParentChange").withArgs(parent.address, parent.address);
    expect(await whitelist.parent()).to.equal(parent.address);
  });

  it("should track whitelisted", async () => {
    await expect(
      await whitelist.whitelist(person.address)
    ).to.emit(whitelist, "Whitelisted").withArgs(person.address, true);
    assert(await whitelist.explicitlyWhitelisted(person.address));
    assert(await whitelist.whitelisted(person.address));
    expect(await whitelist.kyc(person.address)).to.equal(ethers.constants.HashZero);
    expect(await whitelist.removed(person.address)).to.equal(false);
  });

  it("should track KYC", async () => {
    await expect(
      await whitelist.setKYC(person.address, oldInfo, 0)
    ).to.emit(whitelist, "KYCUpdate").withArgs(person.address, ethers.constants.HashZero, oldInfo, 0);
    assert(await whitelist.explicitlyWhitelisted(person.address));
    assert(await whitelist.whitelisted(person.address));
    expect(await whitelist.kyc(person.address)).to.equal(oldInfo);
    expect(await whitelist.removedAt(person.address)).to.equal(0);
    expect(await whitelist.removed(person.address)).to.equal(false);
  });

  it("should support updating KYC hashes", async () => {
    await expect(
      await whitelist.setKYC(person.address, newInfo, 1)
    ).to.emit(whitelist, "KYCUpdate").withArgs(person.address, oldInfo, newInfo, 1);
    assert(await whitelist.explicitlyWhitelisted(person.address));
    assert(await whitelist.whitelisted(person.address));
    expect(await whitelist.kyc(person.address)).to.equal(newInfo);
    expect(await whitelist.removedAt(person.address)).to.equal(0);
    expect(await whitelist.removed(person.address)).to.equal(false);
  });

  it("should nonce KYC hashes", async () => {
    await expect(
      whitelist.setKYC(person.address, newInfo, 1)
    ).to.be.revertedWith(`Replay(1, 2)`);

    await expect(
      await whitelist.setKYC(person.address, newInfo, 2)
    ).to.emit(whitelist, "KYCUpdate").withArgs(person.address, newInfo, newInfo, 2);
  });

  it("should handle removals", async () => {
    await expect(
      await whitelist.remove(person.address)
    ).to.emit(whitelist, "Whitelisted").withArgs(person.address, false);
    expect(await whitelist.explicitlyWhitelisted(person.address)).to.equal(false);
    expect(await whitelist.whitelisted(person.address)).to.equal(false);
    expect(await whitelist.kyc(person.address)).to.equal(newInfo);
    expect(await whitelist.removedAt(person.address)).to.equal((await waffle.provider.getBlock("latest")).number);
    assert(await whitelist.removed(person.address));
  });

  it("should carry parent whitelisting", async () => {
    await parent.whitelist(parentPerson.address);
    assert(await whitelist.whitelisted(parentPerson.address));
    expect(await whitelist.explicitlyWhitelisted(parentPerson.address)).to.equal(false);
  });

  it("should carry parent status", async () => {
    await parent.setKYC(parentPerson.address, newInfo, 0);
    expect(await whitelist.status(parentPerson.address)).to.equal(WhitelistStatus.KYC);
  });

  it("should considered removed even if parent whitelisted", async () => {
    await parent.whitelist(person.address);
    expect(await whitelist.whitelisted(person.address)).to.equal(false);
  })

  it("should support going global", async () => {
    expect(await whitelist.setGlobal()).to.emit(whitelist, "GlobalAcceptance");
    assert(await whitelist.global());
    assert(await whitelist.whitelisted(signers[0].address));
  });
});
