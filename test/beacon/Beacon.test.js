const { ethers } = require("hardhat");
const { expect } = require("chai");

let signer, junk;
let auction, beacon, owned;
let TestUpgradeable, dataless;

const data = (new ethers.utils.AbiCoder()).encode(
  ["address", "bytes"],
  ["0x0000000000000000000000000000000000000003", "0x" + Buffer.from("Upgrade Data").toString("hex")]
);

function upgradeable(version, data) {
  return TestUpgradeable.deploy(version, data);
}

describe("Beacon", () => {
  before(async () => {
    signer = (await ethers.getSigners())[0];
    // Junk address used for testing reversions and unset data
    junk = (await ethers.getSigners()).splice(1, 1)[0].address;

    // This needs to have a valid piece of code and Auction is trivial to deploy
    auction = (await (await ethers.getContractFactory("Auction")).deploy()).address;
    const Beacon = await ethers.getContractFactory("Beacon");
    beacon = await Beacon.deploy(ethers.utils.id("Auction"), 2);
    beacon.implementation = beacon["implementation(address)"];

    owned = await (await ethers.getContractFactory("TestOwnable")).deploy();
    expect(await owned.owner()).to.equal(signer.address);

    TestUpgradeable = await ethers.getContractFactory("TestUpgradeable");
    dataless = await upgradeable(2, false);
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
      await beacon.upgrade(ethers.constants.AddressZero, 1, auction, "0x")
    ).to.emit(beacon, "Upgrade").withArgs(ethers.constants.AddressZero, 1, auction, "0x");

    expect(await beacon.implementations(ethers.constants.AddressZero)).to.equal(auction);
    expect(await beacon.implementation(ethers.constants.AddressZero)).to.equal(auction);
  });

  it("should resolve an address via release channel 0", async () => {
    expect(await beacon.implementations(junk)).to.equal(ethers.constants.AddressZero);
    expect(await beacon.implementation(junk)).to.equal(auction);
  });

  it("should let your set you own code", async () => {
    await expect(
      await beacon.upgrade(signer.address, 2, dataless.address, "0x")
    ).to.emit(beacon, "Upgrade").withArgs(signer.address, 2, dataless.address, "0x");
  });

  it("should let you set code of contracts you own", async () => {
    await expect(
      // This owned contract has a name of TestOwnable, yet that doesn't matter
      // as the Beacon only checks beacon name == new code name. Any instance
      // actually using this beacon will therefore have a name matching as it
      // will be using code specified by this beacon. While we could further
      // check, why waste gas on legitimate calls to prevent instances which
      // don't even use this beacon from having code set which is a non-issue
      await beacon.upgrade(owned.address, 2, dataless.address, "0x")
    ).to.emit(beacon, "Upgrade").withArgs(owned.address, 2, dataless.address, "0x");
  });

  it("shouldn't let you set code of contracts you don't own, even as the owner", async () => {
    // Doesn't exist
    await expect(
      beacon.upgrade(junk, 2, dataless.address, "0x")
    ).to.be.revertedWith(`NotUpgradeAuthority("${signer.address}", "${junk}")`);

    // No owner
    await expect(
      beacon.upgrade(auction, 2, dataless.address, "0x")
    ).to.be.revertedWith(`NotUpgradeAuthority("${signer.address}", "${auction}")`);

    // Different owner
    // Any other address will use, and auction will be distinct and not < releaseChannels
    await owned.transferOwnership(junk);
    await expect(
      beacon.upgrade(owned.address, 2, dataless.address, "0x")
    ).to.be.revertedWith(`NotUpgradeAuthority("${signer.address}", "${owned.address}")`);
  });

  it("should support upgrading with data", async () => {
    const u = await upgradeable(3, true);
    await expect(
      await beacon.upgrade(ethers.constants.AddressZero, 3, u.address, data)
    ).to.emit(beacon, "Upgrade").withArgs(ethers.constants.AddressZero, 3, u.address, data);
    expect(await beacon.upgradeDatas(ethers.constants.AddressZero, 3)).to.equal(data);
    expect(await beacon.upgradeData(ethers.constants.AddressZero, 3)).to.equal(data);

    // Test resolution
    expect(await beacon.upgradeDatas(junk, 3)).to.equal("0x");
    expect(await beacon.upgradeData(junk, 3)).to.equal(data);
  });

  it("should support triggering upgrades", async () => {
    const u = await upgradeable(2, true);
    await expect(
      await beacon.triggerUpgrade(u.address, 3)
    ).to.emit(u, "Triggered").withArgs(3, data);
  });

  it("shouldn't support triggering upgrades for the wrong version", async () => {
    const u = await upgradeable(3, true);
    await expect(
      beacon.triggerUpgrade(u.address, 3)
    ).to.be.revertedWith("InvalidVersion(3, 2)");
  });

  // Does verify the upgrade data is properly verified by TestUpgradeable as expected
  it("should hit full code coverage on TestUpgradeable", async () => {
    const u = await upgradeable(3, true);
    await expect(u.validateUpgrade(2, data)).to.be.revertedWith("1");
    await expect(
      u.validateUpgrade(3, (new ethers.utils.AbiCoder()).encode(
        ["address", "bytes"],
        [
          "0x0000000000000000000000000000000000000002",
          "0x" + Buffer.from("Upgrade Data").toString("hex")
        ]
      ))
    ).to.be.revertedWith("2");
    await expect(
      u.validateUpgrade(3, (new ethers.utils.AbiCoder()).encode(
        ["address", "bytes"],
        [
          "0x0000000000000000000000000000000000000003",
          "0x" + Buffer.from("Different Upgrade Data").toString("hex")
        ]
      ))
    ).to.be.revertedWith("3");
  });
});
