const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

const { proposal, propose } = require("../common.js");
const {FRABRIC, proposalUtils} = require("./VTP_modular");


const GOVERNOR = process.env.GOVERNOR;
const WALLETS = [GOVERNOR]
const utils = proposalUtils ;

module.exports = async () => {

    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider);

    const proposer = signers[0];
    console.log(ethers.utils.isAddress(proposer.address));

    const frabric = await new ethers.Contract(
        FRABRIC.beaconProxy,
        require('../../artifacts/contracts/frabric/Frabric.sol/Frabric.json').abi,
        proposer
    )

    const USD = process.env.USD;
    console.log(USD);
    
    const info = ethers.utils.id("ipfs-info");
    const descriptor = ethers.utils.id("ipfs-descriptor");
    const data = (new ethers.utils.AbiCoder()).encode(
        ["address", "uint112"],
        [USD, 1000]
    );

    const isAddress = ethers.utils.isAddress;

    if(
        isAddress(frabric.address) &&
        isAddress(USD)
    ) {
        console.log("ALL GOOD!!");
        const tx = await frabric.proposeThread(
            0,
            "NAME",
            "SYMBOL",
            descriptor,
            data,
            info
        )
    }
// const {id } = await proposal(frabric, "ThreadProposal", false, [])
}

const callModule = async () => {
    console.log("YESS");
    await module.exports()
}

if (require.main === module) {
    callModule()
}





// console.log(frabric.address);

