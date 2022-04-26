const { ethers } = require("hardhat");
const { expect } = require("chai");

let signer, auction, beacon;

describe("SingleBeacon", () => {
  before(async () => {
    signer = (await ethers.getSigners())[0];

    // This needs to have a valid piece of code and Auction is trivial to deploy
    auction = (await (await ethers.getContractFactory("Auction")).deploy()).address;
    const SingleBeacon = await ethers.getContractFactory("SingleBeacon");
    beacon = await SingleBeacon.deploy(ethers.utils.id("Auction"));
  });

  it("should have the right amount of release channels", async () => {
    expect(await beacon.releaseChannels()).to.equal(1);
  });

  it("should allow upgrading release channel 0", async () => {
    await expect(
      await beacon.upgrade(ethers.constants.AddressZero, 2, auction, "0x")
    ).to.emit(beacon, "Upgrade").withArgs(ethers.constants.AddressZero, 2, auction, "0x");
  });

  it("should only allow upgrading release channel 0", async () => {
    await expect(
      beacon.upgrade("0x0000000000000000000000000000000000000001", 2, auction, "0x")
    ).to.be.revertedWith(`UpgradingInstance("0x0000000000000000000000000000000000000001")`);

    // Use ourselves as the instance as we do have authority to set our own code
    await expect(
      beacon.upgrade(signer.address, 2, auction, "0x")
    ).to.be.revertedWith(`UpgradingInstance("${signer.address}")`);
  });
});
