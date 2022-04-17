const { ethers } = require("hardhat");
const { expect } = require("chai");

let signer, auction, beacon;

describe("Beacon", () => {
  before(async () => {
    signer = (await ethers.getSigners())[0];

    // This needs to have a valid piece of code and Auction is trivial to deploy
    auction = (await (await ethers.getContractFactory("Auction")).deploy()).address;
    const Beacon = await ethers.getContractFactory("Beacon");
    beacon = await Beacon.deploy(ethers.utils.id("Auction"), 2);
    beacon.implementation = beacon["implementation(address)"];
  });

  it("should have the right name and version", async () => {
    expect(await beacon.contractName()).to.equal(ethers.utils.id("Beacon"));
    expect(await beacon.version()).to.equal(ethers.constants.MaxUint256);
  });

  it("should have the right beacon name and number of release channels", async () => {
    expect(await beacon.beaconName()).to.equal(ethers.utils.id("Auction"));
    expect(await beacon.releaseChannels()).to.equal(2);
  });

  it("should allow upgrading release channel 0", async () => {
    await expect(
      beacon.upgrade(ethers.constants.AddressZero, auction, 2, "0x")
    ).to.emit(beacon, "Upgrade").withArgs(ethers.constants.AddressZero, auction, 2, "0x");

    // TODO: Verify implementation and implementations were correctly updated
  });

  it("should resolve release channel 1 via release channel 0", async () => {
    expect(
      await beacon.implementation(ethers.constants.AddressZero)
    ).to.equal(auction);
  });

  it("should resolve an address via release channel 0", async () => {
    expect(
      await beacon.implementation(signer.address)
    ).to.equal(auction);
  });

  it("should let you set you own code", async () => {
    // TODO
  });

  it("should let you set code of contracts you own", async () => {
    // TODO
  });

  it("shouldn't let you set code of contracts you don't own", async () => {
    // TODO
  });

  it("should support beacon forwarding", async () => {
    // TODO
  });

  it("should support upgrading with data", async () => {
    // TODO
  });

  it("should support resolving upgrade data", async () => {
    // TODO

    // TODO with beacon forwarding
  });

  it("should support triggering upgrades", async () => {
    // TODO

    // TODO with beacon forwarding
  });
});
