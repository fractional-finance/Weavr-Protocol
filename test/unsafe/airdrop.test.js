const {ethers, waffle} = require("hardhat");
const {expect} = require("chai");

const {increaseTime} = require("../common.js");
const FrabricERC20 = require("../../scripts/deployFrabricERC20");

let deployer, first, second, third, token, airdrop;

const ExpiryDays = 30;

describe("Airdrop", accounts => {
    before(async () => {
        let signers = await ethers.getSigners();
        [deployer, first, second, third] = signers.splice(0, );

        usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");

        // Deploy a FrabricERC20 which will eventually be set as the parent
        ({ frbc, auction } = await FrabricERC20.deployFRBC(usd.address));
        token = frbc;
        await token.whitelist(first.address);
        await token.whitelist(second.address);
        await token.whitelist(third.address);
        await token.mint(deployer.address, 10000);
    });

    it("Should allow for the deployment of an Airdrop contract with 3 claimants", async () => {
        let airdrop_contract = await ethers.getContractFactory("Airdrop");
        let claimants = [
            first.address,
            second.address,
            third.address
        ]
        let amounts = [
            100,
            100,
            100
        ]
        airdrop = await airdrop_contract.deploy(
            ExpiryDays,
            token.address,
            claimants,
            amounts
        )

        await token.whitelist(airdrop.address);
    });

    it("should allow for another contract to deposit IERC20 tokens", async () => {
        await token.transfer(airdrop.address, 199);
        expect(await token.balanceOf(airdrop.address)).to.equal(199);
    });

    it("Should allow for a claimant to claim their tokens", async () => {
        await airdrop.connect(first).claim();
        expect(await token.balanceOf(first.address)).to.equal(100);
        expect(await airdrop.viewClaim(first.address)).to.equal(0);
    });
    it("Should not allow a claimant to claim twice", async () => {
        await expect(airdrop.connect(first).claim()).to.be.revertedWith(`AlreadyClaimed("${first.address}")`);
    });

    it("Should allow for a claimant to claim the current Airdrop balance if it has less than the claim amount remaining in the contract", async () => {
        await airdrop.connect(second).claim();
        expect(await token.balanceOf(second.address)).to.equal(99);
        expect(await airdrop.viewClaim(second.address)).to.equal(0);
    });
    
    it("Should not allow a claimant to claim after expiry", async () => {
        await increaseTime(ExpiryDays * 86400);
        await expect(airdrop.connect(third).claim()).to.be.revertedWith("Expired()");
    });
    it("should allow non-admin to expire an expired airdrop", async () => {
        await airdrop.expire();
        expect(await token.balanceOf(airdrop.address)).to.equal(0);
    });


});