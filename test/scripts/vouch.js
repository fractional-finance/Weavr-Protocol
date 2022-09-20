const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

const { proposal, propose } = require("../common.js");
const {FRABRIC, proposalUtils} = require("./VTP_modular");

const State = {
    Active: 0,
    Executing: 1,
    Refunding: 2,
    Finished: 3
  }

// const WALLETS = (process.env.WALLETS).split(",");
const KYC = process.env.KYC
const utils = proposalUtils ;
const isAddress = ethers.utils.isAddress;

PARTICIPANT = "0x6Ac7F09FA05f40E229064fA20EF3D27c4c961591"

module.exports = async () => {

    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider, [KYC]);

    const voucher = signers[0];
    console.log(ethers.utils.isAddress(voucher.address));

    const frabric = await new ethers.Contract(
        process.env.INITIALFRABRIC,
        require('../../artifacts/contracts/frabric/Frabric.sol/Frabric.json').abi,
        voucher
    )
    if(isAddress(frabric.address)){
        console.log(frabric.address,"\t", voucher.address);
        console.log("Verifier: ", await frabric.participant(voucher.address))
        const data = ethers.utils.id("verifying zeryx")
        console.log("contract: ", await frabric.contractName(),"\n", data);
        if( !(await frabric.canPropose(PARTICIPANT)) ){
            console.log("Verifying participant.... ", PARTICIPANT)
            const tx = await frabric.verify(6, PARTICIPANT, data, { gasLimit: 300000});
        tx ? console.log(tx) : console.log("something went wrong");;    
        }else {
            console.log("Participant is verifyed");
        }
        
    }
    
    
}

const callModule = async () => {
    console.log("YESS");
    await module.exports()
}

if (require.main === module) {
    callModule()
}
