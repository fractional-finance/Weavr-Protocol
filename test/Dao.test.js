const { assert } = require("chai");

require("chai")
    .use(require("bn-chai")(web3.utils.BN))
    .use(require("chai-as-promised"))
    .should();

let IntegratedDAO = artifacts.require("StubbedDao");

contract("IntegratedDAO", accounts=> {
    let holder = accounts[0];
    let other = accounts[1];
     it("Should be able to propose a Paper Proposal", async () => {
         let payload = web3.utils.asciiToHex({"title": "Proposal Title", "description": "Proposal Description", "tags": ["tag1", "tag2"]}.toString());
         let dao = await IntegratedDAO.new();
         let tx = await dao.proposePaper(payload, {from: holder});
         assert.equal(tx.logs[0].event, "NewProposal");
         assert.equal(tx.logs[0].args.id.toNumber(), 0);
         assert.equal(tx.logs[0].args.creator, holder);
         assert.equal(tx.logs[0].args.info, payload);
     });

    it("Should be able to vote on a proposal", async () => {
        let payload = web3.utils.asciiToHex({"title": "Proposal Title", "description": "Proposal Description", "tags": ["tag1", "tag2"]}.toString());
        let dao = await IntegratedDAO.new();
        let token_qty = 100;
        let smalL_token_qty = 1;
        await dao.transfer(other, token_qty, {from: holder});
        let tx1 = await dao.proposePaper(payload, {from: holder});
        await dao.transfer(other, smalL_token_qty, {from: holder});
        let tx2 = await dao.voteYes(tx1.logs[0].args.id.toNumber(), {from: other})
        assert.equal(tx2.logs[0].event, "YesVote", "voteYes event not emitted");
        assert.equal(tx2.logs[0].args.votes.toNumber(), token_qty, "voteYes event emitted with incorrect number of votes");
    });

    it("Should be able to withdrawal a proposal", async () => {
        let payload = web3.utils.asciiToHex({"title": "Proposal Title", "description": "Proposal Description", "tags": ["tag1", "tag2"]}.toString());
        let dao = await IntegratedDAO.new();
        let tx1 = await dao.proposePaper(payload, {from: holder});
        let tx2 = await dao.withdrawProposal(tx1.logs[0].args.id.toNumber());
        assert.equal(tx2.logs[0].event, "Withdrawal", "withdrawalProposal event not emitted");
        assert.equal(tx2.logs[0].args.id.toNumber(), 0, "withdrawalProposal event emitted with incorrect id");
       });

    it("Should be able to propose a Buyout/Dissolution", async () => {
        let payload = web3.utils.asciiToHex({"title": "Proposal Title", "description": "Proposal Description", "tags": ["tag1", "tag2"]}.toString());
        let dao = await IntegratedDAO.new();
        let tx1 = await dao.proposeDissolution(payload, {from: holder});
        assert.equal(tx1.logs[0].event, "NewProposal", "NewProposal event not emitted");
        assert.equal(tx1.logs[0].args.id.toNumber(), 0, "NewProposal event emitted with incorrect id");
        assert.equal(tx1.logs[0].args.creator, holder, "NewProposal event emitted with incorrect creator");
        assert.equal(tx1.logs[0].args.info, payload, "NewProposal event emitted with incorrect info");
    });

    it("Should be able to reclaim funds on failed dissolution", async () => {
        let payload = web3.utils.asciiToHex({"title": "Proposal Title", "description": "Proposal Description", "tags": ["tag1", "tag2"]}.toString());
        let dao = await IntegratedDAO.new();
        let tx1 = await dao.proposeDissolution(payload, {from: holder});
        setTimeout(async () => {
            let tx2 = await dao.reclaimFunds(tx1.logs[0].args.id.toNumber());
            assert.equal(tx2.logs[0].event, "ReclaimFunds");
            assert.equal(tx2.logs[0].args.id.toNumber(), 0);
        }, 1000);
    });

     it("Should be able to vote on proposal", async () => {
         let dao = await IntegratedDAO.new()
         await dao._createProposal("{\"info\": \"bar\"}", 10, 1, {from: holder});
         await dao.voteYes(1, 1, {from: holder});
         await dao.voteNo(1, 1, {from: holder});
     });

     it("Non-permitted users should not be able to vote on proposal", async () => {
         let dao = await IntegratedDAO.new()
         await dao._createProposal("{\"info\": \"bar\"}", 10, 1, {from: holder});
         await dao.voteYes(1, 1, {from: accounts[1]});
         await dao.voteNo(1, 1, {from: accounts[1]});
     });

    it("External user should be able to view the current status of a proposal", async () => {});

    it("Proposal's voting period should terminate after 30 days", async () => {});

});