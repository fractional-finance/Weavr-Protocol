const { ethers, waffle } = require("hardhat");
const { assert, expect } = require("chai");

const { impermanent, mine } = require("../common.js");

let signers, deployer, other, token;

const MILLION = ethers.utils.parseUnits("1000000");

describe("DistributionERC20", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    deployer = signers.splice(0, 1)[0];

    token = await (await ethers.getContractFactory("TestDistributionERC20")).deploy("Token", "TEST");
    other = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");
  });

  it("should not allow delegation", async () => {
    await expect(token.delegate(signers[0].address)).to.be.revertedWith("Delegation()");

    const types = {
      Delegation: [
        { name: "delegatee", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "expiry", type: "uint256" }
      ]
    };
    const expiry = (await waffle.provider.getBlock("latest")).timestamp + 30;
    const value = {
      delegatee: signers[0].address,
      nonce: 0,
      expiry
    };
    let sig;
    if (deployer._signTypedData) {
      sig = await deployer._signTypedData({}, types, value);
    } else {
      sig = await deployer.signTypedData({}, types, value);
    }
    sig = ethers.utils.splitSignature(sig);

    await expect(
      token.delegateBySig(signers[0].address, 0, expiry, sig.v, sig.r, sig.s)
    ).to.be.revertedWith("Delegation()");
  });

  it("should have the correct initial vote/balance value", async () => {
    expect(await token.totalSupply()).to.equal(MILLION);
    expect(await token.balanceOf(deployer.address)).to.equal(MILLION);

    let number = (await waffle.provider.getBlock("latest")).number;
    // Explicitly mine a block as Hardhat is calling using the last block number,
    // not the theoretical next an actual TX would be included in
    await mine(1);

    expect(await token.getPastTotalSupply(number)).to.equal(MILLION);
    expect(await token.getPastVotes(deployer.address, number)).to.equal(MILLION);
  });

  it("should correctly update on transfer", async () => {
    await expect(
      await token.transfer(signers[0].address, 1)
    ).to.emit(token, "Transfer").withArgs(deployer.address, signers[0].address, 1);
    expect(await token.balanceOf(deployer.address)).to.equal(MILLION.sub(1));
    expect(await token.balanceOf(signers[0].address)).to.equal(1);

    let number = (await waffle.provider.getBlock("latest")).number;
    await mine(1);

    expect(await token.getPastVotes(deployer.address, number)).to.equal(MILLION.sub(1));
    expect(await token.getPastVotes(signers[0].address, number)).to.equal(1);

    // Perfect state. Could also use a snapshot
    await token.connect(signers[0]).transfer(deployer.address, 1);
  });

  it("should ban fee on transfer", async () => {
    // TODO
  });

  // Single recipient
  it("should handle distributions", async () => {
    await other.approve(token.address, ethers.utils.parseUnits("100"));

    await expect(
      await token.distribute(other.address, ethers.utils.parseUnits("100"))
    ).to.emit(token, "Distribution").withArgs(0, other.address, ethers.utils.parseUnits("100"));

    expect(await token.claimed(0, deployer.address)).to.equal(false);

    // Connect with a different address to verify anyone can trigger a claim for anyone
    const tx = await token.connect(signers[0]).claim(0, deployer.address);
    await expect(tx).to.emit(token, "Claim").withArgs(0, deployer.address, ethers.utils.parseUnits("100"));
    await expect(tx).to.emit(other, "Transfer").withArgs(token.address, deployer.address, ethers.utils.parseUnits("100"));
    expect(await other.balanceOf(token.address)).to.equal(0);
    assert(await token.claimed(0, deployer.address));
  });

  it("shouldn't allow claiming multiple times", async () => {
    await expect(token.claim(0, deployer.address)).to.be.revertedWith(`AlreadyClaimed(0, "${deployer.address}")`);
  })

  // 3 recipients
  it("should handle distributions to multiple parties", impermanent(async () => {
    let amounts = [
      "333333333333333333333333",
      "333333333333333333333333",
      "333333333333333333333334"
    ];
    const sub = signers.slice(0, 3);
    await token.transfer(sub[0].address, amounts[0]);
    await token.transfer(sub[1].address, amounts[1]);
    await token.transfer(sub[2].address, amounts[2]);
    expect(await token.balanceOf(deployer.address)).to.equal(0);

    await other.approve(token.address, ethers.utils.parseUnits("1000"));
    await expect(
      await token.distribute(other.address, ethers.utils.parseUnits("1000"))
    ).to.emit(token, "Distribution").withArgs(1, other.address, ethers.utils.parseUnits("1000"));

    for (let i = 0; i < 3; i++) {
      let address = sub[i].address;
      let amount = ethers.BigNumber.from(amounts[1]).div("1000");
      expect(amount).to.equal("333333333333333333333");
      const tx = await token.claim(1, address);
      await expect(tx).to.emit(token, "Claim").withArgs(1, address, amount);
      await expect(tx).to.emit(other, "Transfer").withArgs(token.address, address, amount);
      assert(await token.claimed(1, address));
      expect(await other.balanceOf(address)).to.equal(amount);
    }
    expect(await other.balanceOf(token.address)).to.equal(1);
  }));

  // Fuzz
  it("should handle distributions to variable parties", async () => {
    // TODO
  });
});
