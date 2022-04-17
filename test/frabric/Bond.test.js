const { ethers, waffle, network } = require("hardhat");

const { MerkleTree } = require("merkletreejs");

const deployBond = require("../../scripts/deployBond.js");

const { assert, expect } = require("chai");

const { GovernorStatus } = require("../common.js");

let signers, deployer, governor;
let usdc, pair;
let bond, frabric;

describe("Bond", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [deployer, governor] = signers.splice(0, 2);

    usdc = await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD");
    pair = await (await ethers.getContractFactory("TestERC20")).deploy("Bond Test", "BOND");

    // Deploy the bond contract
    // TODO: Check the events/behavior from init
    const { proxy, bond: bondContract } = await deployBond(usdc.address, pair.address);
    bond = bondContract;

    // Deploy a TestFrabric
    frabric = await (await ethers.getContractFactory("TestFrabric")).deploy();
    await bond.transferOwnership(frabric.address);
  });

  it("shouldn't let non-active-governors add bond", async () => {
    await expect(
      bond.bond(100)
    ).to.be.revertedWith(`NotActiveGovernor("${deployer.address}", 0)`);
  });

  it("should let active governors add bond", async () => {
    await frabric.setGovernor(governor.address, GovernorStatus.Active);
    await pair.transfer(governor.address, 100);
    await pair.connect(governor).approve(bond.address, 100);
    await expect(
      await bond.connect(governor).bond(100)
    ).to.emit(bond, "Bond").withArgs(governor.address, 100);
    expect(await pair.balanceOf(governor.address)).to.be.equal(0);
    expect(await pair.balanceOf(bond.address)).to.be.equal(100);
    expect(await bond.balanceOf(governor.address)).to.be.equal(100);
  });

  it("shouldn't let you call unbond", async () => {
    await expect(
      bond.unbond(governor.address, 100)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("shouldn't let you call slash", async () => {
    await expect(
      bond.slash(governor.address, 100)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should let the Frabric call unbond", async () => {
    // TODO
  });

  it("should let the Frabric call slash", async () => {
    // TODO
  });

  it("shouldn't let you recover the bond token", async () => {
    await expect(
      bond.recover(pair.address)
    ).to.be.revertedWith(`RecoveringBond("${pair.address}")`);
  });

  it("should let you recover arbitrary tokens", async () => {
    await usdc.transfer(bond.address, 1);
    await expect(
      await bond.recover(usdc.address)
    ).to.emit(usdc, "Transfer").withArgs(bond.address, frabric.address, 1);
    expect(await usdc.balanceOf(frabric.address)).to.be.equal(1);
  });

  it("shouldn't let you transfer the bond token", async () => {
    await expect(
      bond.connect(governor).transfer(deployer.address, 1)
    ).to.be.revertedWith(`BondTransfer()`);
  });
});
