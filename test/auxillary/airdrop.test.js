const {ethers, waffle} = require("hardhat");
const {expect} = require("chai");

const {increaseTime} = require("../common.js");

let deployer, other, token, airdrop;

const ExpiryDays = 30;

describe("Airdrop", accounts => {
    before(async () => {
        let signers = await ethers.getSigners();
        [deployer, other] = signers.splice(0, 2);

        token = await (await ethers.getContractFactory("TestERC20Burnable")).deploy("Test Burnable USD", "TUSD");
        airdrop = await (await ethers.getContractFactory("Airdrop")).deploy(ExpiryDays, token.address);
    });

    it("should allow for another contract to deposit IERC20 tokens", async () => {
        await token.transfer(airdrop.address, 1000);
        expect(await token.balanceOf(airdrop.address)).to.equal(1000);
    });

    it("Should allow for owner to add a claim for user", async () => {
        await airdrop.addClaim([other.address], [100]);
        expect(await airdrop.viewClaim(other.address)).to.equal(100);
    });
    it("Should allow for a claimant to claim their tokens", async () => {
        await airdrop.connect(other).claim();
        expect(await token.balanceOf(other.address)).to.equal(100);
        expect(await airdrop.viewClaim(other.address)).to.equal(0);
    });
    it("Should not allow a claimant to claim twice", async () => {
        await expect(airdrop.connect(other).claim()).to.be.revertedWith(`AlreadyClaimed(100, "${other.address}")`);
    });
    it("Should not allow a claimant to claim after expiry", async () => {
        await increaseTime(ExpiryDays * 86400);
        await expect(airdrop.connect(other).claim()).to.be.revertedWith("Expired()");
    });
    it("should allow non-admin to expire an expired airdrop", async () => {
        await airdrop.expire();
        expect(await token.balanceOf(airdrop.address)).to.equal(0);
    });


});