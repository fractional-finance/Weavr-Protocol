const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

const { proposal, propose } = require("../common.js");
const {FRABRIC, proposalUtils} = require("./VTP_modular");


const GOVERNOR = process.env.GOVERNOR;
const WALLETS = (process.env.WALLETS).split(",");

const utils = proposalUtils ;

module.exports = async () => {

    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider, [GOVERNOR]);

    const proposer = signers[0];
    console.log(
        "\n\n",
        "ADDRESS\t", 
        proposer.address, " is ", 
        ethers.utils.isAddress(proposer.address) ? 
            "valid" : "not valid"
    );

    const frabric = await new ethers.Contract(
        process.env.INITIALFRABRIC,
        require('../../artifacts/contracts/frabric/Frabric.sol/Frabric.json').abi,
        proposer
    )

    console.log(    
        await frabric.canPropose(proposer.address) ?
            "\t\tcan propose!" : "- not allowed to propose!!!"
    )

    const USD = process.env.USD;
    console.log("USD: ",USD);
    
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
        console.log(
            "\n\n",
            "READY TO PROPOSE \n\n", 
            "PAYLOAD:\n",
            {
                variant: ethers.BigNumber.from(0),
                name: "THREAD2",
                symbol: "SMBL2",
                descriptor: descriptor,
                data: data,
                info: info
            }

        );
        const tx = await frabric.proposeThread(
            ethers.BigNumber.from(0),
            "THREAD2",
            "SMBL2",
            descriptor,
            data,
            info
        )
        console.log(tx)
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

