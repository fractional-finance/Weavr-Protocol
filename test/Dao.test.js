const { assert } = require("chai");

require("chai")
    .use(require("bn-chai")(web3.utils.BN))
    .use(require("chai-as-promised"))
    .should();

let StubbedDao = artifacts.require("StubbedDao");

contract("IntegratedDAO", (accounts) => {
    let dao = StubbedDao.new();
    let holder = accounts[0];

    it ("Should be able to propose a Paper Proposal", async () => {});

    it("Should be able to propose a Platform Change", async () => {});

    it("Should be able to propose an Oracle Change", async () => {});

    it("Should be able to propose a Buyout/Dissolution", async () => {});

    it("Should be able to reclaim funds on failed dissolution", async () => {});

    it ("Should not be able to propose a Proposal if not permitted user", async () => {});

    it("Should be able to vote on proposal", async () => {});

    it("Non-permitted users should not be able to vote on proposal", async () => {});

    it("External user should be able to view the current status of a proposal", async () => {});

    it("Proposal's voting period should terminate after 30 days", async () => {});



}