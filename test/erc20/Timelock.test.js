const { ethers, waffle } = require("hardhat");
const { expect } = require("chai");

const { increaseTime } = require("../common.js");

let deployer, other, token;

const MONTH = 30 * 24 * 60 * 60;
let next;

describe("Timelock", accounts => {
  before(async () => {
    let signers = await ethers.getSigners();
    [deployer, other] = signers.splice(0, 2);

    token = await (await ethers.getContractFactory("TestERC20")).deploy("Token", "TEST");
    timelock = await (await ethers.getContractFactory("Timelock")).deploy();
  });

  it("should allow recovering tokens accidentally sent", async () => {
    await token.transfer(timelock.address, 15);
    await token.transfer(other.address, await token.balanceOf(deployer.address));
    await expect(
      await timelock.claim(token.address)
    ).to.emit(timelock, "Claim").withArgs(token.address, 15);
    expect(await token.balanceOf(timelock.address)).to.equal(0);
    expect(await token.balanceOf(deployer.address)).to.equal(15);
  });

  it("shouldn't let anyone set a lock", async () => {
    await expect(
      timelock.connect(other).lock(token.address, 1)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should let the owner set a lock", async () => {
    await token.transfer(timelock.address, 15);
    await expect(
      await timelock.lock(token.address, 6)
    ).to.emit(timelock, "Lock").withArgs(token.address, 6);
    next = (await waffle.provider.getBlock("latest")).timestamp + MONTH;
    expect(await timelock.nextLockTime(token.address)).to.equal(next);
    expect(await timelock.remainingMonths(token.address)).to.equal(6);
  });

  it("shouldn't allow claiming before the lock expires", async () => {
    // Works for the time used in the below call
    const time = (await waffle.provider.getBlock("latest")).timestamp + 1;
    await expect(
      timelock.claim(token.address)
    ).to.be.revertedWith(`Locked("${token.address}", ${time}, ${next})`);
  });

  it("should allow claiming when the lock expires", async () => {
    let sum = 0;
    let remaining = await timelock.remainingMonths(token.address)
    while (remaining != 0) {
      await increaseTime(MONTH);

      // Verify it sent the amount remaining divided by the amount of remaining months
      let amount = Math.floor((15 - sum) / remaining);
      await expect(
        await timelock.claim(token.address)
      ).to.emit(timelock, "Claim").withArgs(token.address, amount);
      sum += amount;
      expect(await token.balanceOf(deployer.address)).to.equal(sum);

      // Also check the nextLockTime/remainingMonths fields
      next += MONTH;
      expect(await timelock.nextLockTime(token.address)).to.equal(next);
      expect(await timelock.remainingMonths(token.address)).to.equal(remaining - 1);
      remaining = await timelock.remainingMonths(token.address);
    }
  });
});
