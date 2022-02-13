const { assert } = require("chai");

require("chai")
    .use(require("bn-chai")(web3.utils.BN))
    .use(require("chai-as-promised"))
    .should();

let IntegratedDAO = artifacts.require("StubbedDao");
let erc20 = artifacts.require("ERC20Instance");

contract("IntegratedDAO", accounts=> {
    let holder = accounts[0];
    let other = accounts[1];
    const sleep = (milliseconds) => {
        return new Promise(resolve => setTimeout(resolve, milliseconds))
    }
    let proposal_payload = web3.utils.asciiToHex({"foo":"bar"}.toString());
     it("Should be able to propose a Paper Proposal", async () => {
         let dao = await IntegratedDAO.new();
         let tx = await dao.proposePaper(proposal_payload, {from: holder});
         assert.equal(tx.logs[0].event, "NewProposal");
         assert.equal(tx.logs[0].args.id.toNumber(), 0);
         assert.equal(tx.logs[0].args.creator, holder);
         assert.equal(tx.logs[0].args.info, proposal_payload);
     });

    it("Should be able to vote on a proposal", async () => {
        let dao = await IntegratedDAO.new();
        let token_qty = 100;
        await dao.transfer(other, token_qty, {from: holder});
        let tx1 = await dao.proposePaper(proposal_payload, {from: holder});
        let tx2 = await dao.voteYes(tx1.logs[0].args.id.toNumber(), {from: other})
        assert.equal(tx2.logs[0].event, "YesVote", "voteYes event not emitted");
        assert.equal(tx2.logs[0].args.votes.toNumber(), token_qty, "voteYes event emitted with incorrect number of votes");
    });

    it("Should be able to withdrawal a proposal", async () => {
        let dao = await IntegratedDAO.new();
        let tx1 = await dao.proposePaper(proposal_payload, {from: holder});
        let tx2 = await dao.withdrawProposal(tx1.logs[0].args.id.toNumber());
        assert.equal(tx2.logs[0].event, "ProposalWithdrawn", "withdrawalProposal event not emitted");
        assert.equal(tx2.logs[0].args.id.toNumber(), 0, "withdrawalProposal event emitted with incorrect id");
       });

    it("Should be able to propose a Buyout/Dissolution", async () => {
        let purchase_amount = 100;
        let dao = await IntegratedDAO.new();
        let token = await erc20.new({from: holder});
        await token.approve(dao.address, 100, {from: holder});
        let tx1 = await dao.proposeDissolution(proposal_payload, holder, token.address, purchase_amount, {from: holder, gasLimit: 1000000});
        assert.equal(tx1.logs[0].event, "NewProposal", "NewProposal event not emitted");
        assert.equal(tx1.logs[0].args.id.toNumber(), 0, "NewProposal event emitted with incorrect id");
        assert.equal(tx1.logs[0].args.creator, holder, "NewProposal event emitted with incorrect creator");
        assert.equal(tx1.logs[0].args.info, proposal_payload, "NewProposal event emitted with incorrect info");
    });

    it("Should be able to reclaim funds on failed dissolution", async () => {
        let purchase_amount = 100;
        let dao = await IntegratedDAO.new();
        let token = await erc20.new({from: holder});
        await token.approve(dao.address, 100, {from: holder});
        let tx1 = await dao.proposeDissolution(proposal_payload, holder, token.address, purchase_amount, {from: holder, gasLimit: 1000000});
        await sleep(2000);
        await dao.reclaimDissolutionFunds(tx1.logs[0].args.id.toNumber());
        let balance = await token.balanceOf(holder);
        let total_supply = await token.totalSupply();
        assert.equal(balance.toString(), total_supply.toString(), "ReclaimFunds event emitted with incorrect amount");
    });


    it("External user should be able to view the current status of a proposal", async () => {
    });

    it("Proposal's voting period should terminate after 30 days", async () => {});

});