const { ethers } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { snapshot, revert, increaseTime } = require("../common.js");

const ONE = ethers.utils.parseUnits("1");
const WEEK = 7 * 24 * 60 * 60;
const INFO = ethers.utils.id("info");

let signers, deployer, other;
let usd, auction, frbc, parent;

describe("FrabricERC20", () => {
  before(async () => {
    signers = await ethers.getSigners();
    ([ deployer, other ] = signers.splice(0, 2));

    usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");

    ({ auction, frbc } = await FrabricERC20.deployFRBC(usd.address));

    ({ frbc: parent } = await FrabricERC20.deployFRBC(usd.address));
  });

  it("should have initialized properly", async () => {
    expect(await frbc.name()).to.equal("Frabric Token");
    expect(await frbc.symbol()).to.equal("FRBC");
    expect(await frbc.parent()).to.equal(ethers.constants.AddressZero);
    expect(await frbc.tradeToken()).to.equal(usd.address);
    expect(await frbc.auction()).to.equal(auction.address);

    expect(await frbc.totalSupply()).to.equal(0);
  });

  it("should allow minting", async () => {
    await expect(
      await frbc.mint(deployer.address, 1)
    ).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, deployer.address, 1);
    expect(await frbc.balanceOf(deployer.address)).to.equal(1);
    expect(await frbc.totalSupply()).to.equal(1);
  });

  it("should not allow minting to exceed uint112", async () => {
    await expect(
      // OpenZeppelin's code has a max of uint224 at which errors occur
      // Our test values therefore need to be below that to test our error
      frbc.mint(deployer.address, ethers.constants.MaxUint256.mask(224).sub(2))
    ).to.be.revertedWith(
      `SupplyExceedsInt112(${ethers.constants.MaxUint256.mask(224).sub(1)}, 2596148429267413814265248164610047)`
    );
  });

  it("shouldn't allow transfers to non-whitelisted people", async () => {
    await expect(
      frbc.transfer(other.address, 1)
    ).to.be.revertedWith(`NotWhitelisted("${other.address}")`);
  });

  it("should handle whitelisting", async () => {
    await frbc.setWhitelisted(other.address, INFO);
    expect(await frbc.info(other.address)).to.equal(INFO);
  });

  it("should allow transferring", async () => {
    await expect(
      await frbc.transfer(other.address, 1)
    ).to.emit(frbc, "Transfer").withArgs(deployer.address, other.address, 1);
    expect(await frbc.balanceOf(deployer.address)).to.equal(0);
    expect(await frbc.balanceOf(other.address)).to.equal(1);
  });

  it("should allow burning", async () => {
    await expect(
      await frbc.connect(other).burn(1)
    ).to.emit(frbc, "Transfer").withArgs(other.address, ethers.constants.AddressZero, 1);
  });

  it("should allow freezing and then shouldn't allow them to transfer", async () => {
    await frbc.mint(other.address, 1);

    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await expect(
      await frbc.freeze(other.address, time + 60)
    ).to.emit(frbc, "Freeze").withArgs(other.address, time + 60);
    expect(await frbc.frozenUntil(other.address)).to.equal(time + 60);

    await expect(
      frbc.connect(other).transfer(deployer.address, 1)
    ).to.be.revertedWith(`Frozen("${other.address}")`);
  });

  it("should successfully unfreeze when enough time passes", async () => {
    await increaseTime(60);
    await expect(
      await frbc.connect(other).transfer(deployer.address, 1)
    ).to.emit(frbc, "Transfer").withArgs(other.address, deployer.address, 1);
  });

  it("shouldn't allow transferring locked tokens", async () => {
    await frbc.mint(other.address, ONE.add(1));
    await frbc.connect(other).sell(1, 1);
    expect(await frbc.locked(other.address)).to.equal(ONE);
    await expect(
      frbc.connect(other).transfer(deployer.address, 2)
    ).to.be.revertedWith(`Locked("${other.address}", ${ONE.sub(1)}, ${ONE})`);
  });

  it("should allow transferring tokens which aren't locked even if you have a locked balance", async () => {
    await expect(
      await frbc.connect(other).transfer(deployer.address, 1)
    ).to.emit(frbc, "Transfer").withArgs(other.address, deployer.address, 1);
  });

  it("shouldn't bother removing if they don't have anything to remove", async () => {
    await expect(
      frbc.triggerRemoval(signers[0].address)
    ).to.be.revertedWith(`NothingToRemove("${signers[0].address}")`);
  });

  it("shouldn't still allow removing even if they don't have anything to remove if explicit", async () => {
    await expect(
      await frbc.remove(signers[0].address, 0)
    ).to.emit(frbc, "Removal").withArgs(signers[0].address, 0);
    assert(await frbc.removed(signers[0].address));
    signers.splice(0, 1);
  });

  it("should allow removing", async () => {
    // Mint a balance which isn't locked
    await frbc.mint(other.address, 100);
    // The entire balance, including that on the DEX, should be removed
    const balance = ONE.add(100);

    for (let i = 0; i < 2; i++) {
      let removalFee = ethers.BigNumber.from(0);
      if (i === 1) {
        removalFee = balance.mul(5).div(100);
      }
      const listed = balance.sub(removalFee);

      const id = await snapshot();
      const tx = await frbc.remove(other.address, i * 5);
      await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, auction.address, listed);
      if (i === 1) {
        // deployer is the contract owner and the owner gets the removal fee
        await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, deployer.address, removalFee);
      }
      let start = (await waffle.provider.getBlock("latest")).timestamp;
      for (let b = 0; b < 4; b++) {
        await expect(tx).to.emit(auction, "Listing").withArgs(
          b,
          other.address,
          frbc.address,
          usd.address,
          b !== 3 ? listed.div(4) : listed.sub(listed.div(4).mul(3)),
          start,
          WEEK
        );
        start += WEEK;
      }
      await expect(tx).to.emit(frbc, "Removal").withArgs(other.address, balance);
      expect(await frbc.whitelisted(other.address)).to.equal(false);
      expect(await frbc.balanceOf(other.address)).to.equal(0);
      expect(await frbc.locked(other.address)).to.equal(0);
      assert(await frbc.removed(other.address));
      await revert(id);
    }
  });

  it("should handle setting a new parent", async () => {
    await expect(
      await frbc.setParent(parent.address)
    ).to.emit(frbc, "ParentChange").withArgs(ethers.constants.AddressZero, parent.address);
  });

  it("should allow freezing if the parent froze", async () => {
    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await parent.freeze(other.address, time + 120);
    await expect(
      await frbc.triggerFreeze(other.address)
    ).to.emit(frbc, "Freeze").withArgs(other.address, time + 120);
    expect(await frbc.frozenUntil(other.address)).to.equal(time + 120);
  });

  it("should allow removing if the parent removed", async () => {
    const id = await snapshot();

    let other = signers[0];
    await parent.setWhitelisted(other.address, INFO);
    await parent.mint(other.address, 1);
    await frbc.mint(other.address, ONE);
    await parent.remove(other.address, 10);

    const balance = await frbc.balanceOf(other.address);
    const removalFee = balance.div(10);
    const listed = balance.sub(removalFee);

    const tx = await frbc.triggerRemoval(other.address);
    await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, auction.address, listed);
    await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, deployer.address, removalFee);
    let start = (await waffle.provider.getBlock("latest")).timestamp;
    for (let b = 0; b < 4; b++) {
      await expect(tx).to.emit(auction, "Listing").withArgs(
        b,
        other.address,
        frbc.address,
        usd.address,
        b !== 3 ? listed.div(4) : listed.sub(listed.div(4).mul(3)),
        start,
        WEEK
      );
      start += WEEK;
    }
    await expect(tx).to.emit(frbc, "Removal").withArgs(other.address, balance);
    expect(await frbc.whitelisted(other.address)).to.equal(false);
    expect(await frbc.balanceOf(other.address)).to.equal(0);
    expect(await frbc.locked(other.address)).to.equal(0);

    await revert(id);
  });

  it("should allow pausing and then shouldn't allow transfers", async () => {
    await frbc.pause();
    await expect(frbc.transfer(other.address, 1)).to.be.revertedWith("CurrentlyPaused()");
  });
});
