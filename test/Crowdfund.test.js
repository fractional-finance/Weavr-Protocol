/*
const { ethers } = require("hardhat");
const { assert } = require("chai");

require("chai")
    .use(require("bn-chai")(require("web3").utils.BN))
    .use(require("chai-as-promised"))
    .should();

let crowdfund = ethers.getContractFactory("Crowdfund");
let erc20 = ethers.getContractFactory("ERC20");

describe("Crowdfund Positive Test Cases", accounts => {
    it("Should launch a crowdfund with a non-zero fundraising target", async () => {});
    it("Should launch a crowdfund with a retained ownership %", async () => {});
    it("Should deposit tokens as a new backer", async () => {});
    it("Should withdraw tokens as an existing backer", async () => {});
    it("Should trigger executing status if crowdfunding target was reached, and was previously active", async () => {});
    it("Should allow agent to trigger refunding status if was previously executing", async () => {});
    it("Should allow agent to trigger finished status if was previously executing", async () => {});
    it("Should allow backers to withdraw their funds if the crowdfund status is refunding, and burn their crowdfund ERC20 tokens", async () => {});
    it("Should transfer total balance to agent when state changes to executing status", async () => {});
    it("Should burn backer crowdfund tokens when state changes to finished status", async () => {});
});

describe("Crowdfund Negative Test Cases", accounts => {
    it("Should not be allowed to back a crowdfund that has ended", async () => {});
    it("Should not be allowed to withdraw funds from a crowdfund that is executing", async () => {});
    it("Should not be allowed to withdraw funds from a crowdfund that has ended", async () => {});
});
*/
