const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

const { proposal, propose } = require("../common.js");
const {FRABRIC, proposalUtils} = require("./VTP_modular");


const GOVERNOR = process.env.GOVERNOR;
const WALLETS = [GOVERNOR]
const utils = proposalUtils ;

module.exports = async () => {

    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider, WALLETS);

    const proposer = signers[0];
    console.log(ethers.utils.isAddress(proposer.address));

    const threadDeployer = await new ethers.Contract(
        "0x04F8679236B648bbCdaffc9A247312CD3C7d7aEd",
        require('../../artifacts/contracts/thread/ThreadDeployer.sol/ThreadDeployer.json').abi,
        proposer
    )

    const USD = process.env.USD;
    console.log(USD);
    
    const crowdfundEvents = (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()));
        crowdfundEvents.forEach(event => {
            console.log(event.args);
        });
}

const callModule = async () => {
    console.log("YESS");
    await module.exports()
}

if (require.main === module) {
    callModule()
}





// console.log(frabric.address);

