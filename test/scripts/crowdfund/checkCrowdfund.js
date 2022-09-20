const { ethers, upgrades } = require("hardhat");
const { assert, expect, util } = require("chai");

const { proposal, propose } = require("../../common.js");
const {FRABRIC, proposalUtils} = require("../VTP_modular");

const State = {
    Active: 0,
    Executing: 1,
    Refunding: 2,
    Finished: 3
  }
const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
const GOVERNOR = process.env.GOVERNOR;
const WALLETS = (process.env.WALLETS).split(",");
const utils = proposalUtils ;
const isAddress = ethers.utils.isAddress;
const CROWDFUND = {
    utils: {
        /**
         * 
         * @param {Contract} threadDeployer ThreadDeployer Contract Object
         * @param {{id, return, proposer}} _config  Operational Configs if none will get the latest thread deployed 
         *                                          by the ThreadDeployer and print the args in console
         * @returns CrowdfundContract if config.return is setup and differs from 'ADDRESS'
         */
        getCrowdfundedThread: async(threadDeployer, _config) => {
            let config = !_config ? 
                {
                    id: null, 
                    return: null,
                    proposer: null
                }  : 
                {
                    id: _config.id || null,
                    return: _config.return || null,
                    proposer: _config.proposer || await utils.walletSetup(provider, [GOVERNOR]) || null
                }
            
            const crowdfundEvents = (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()));
            if(config.id == null || config.id == "LAST" || config.id == -1)
                {
                    config.id = crowdfundEvents.length - 1
                } 
                else {
                    if (config.id == "FIRST") {
                        config.id = 0
                    }
                }
            
            
            let _event = crowdfundEvents[config.id];
            
            const print = () => {
                console.log(_event.args);
                console.log("Crowdfund.address: ",  _event.args.crowdfund);
            }

            if(config.return == null || config.return == 0 || config.return == "PRINT"){
                print();
            }else {
                if(config.return == "ADDRESS" || config.return == "address" || config.return == "Address" ) {
                    return _event.args.crowdfund;
                }
                if (!isAddress(config.proposer.address)) {
                    console.log("Governor not present in config.proposer");
                    return new Error("Governor not present in config.proposer")
                }else {
                    crowdfund = await new ethers.Contract( _event.args.crowdfund,
                        require('../../../artifacts/contracts/thread/Crowdfund.sol/Crowdfund.json').abi,
                        config.proposer
                    )
                    console.log("returns: CrowdfundContract");
                    return crowdfund;    
                }
                
            }
        }
    }
}

module.exports = async () => {
    
    const signers = utils.walletSetup(provider, [GOVERNOR].concat(WALLETS));

    const proposer = signers[1];
    console.log(ethers.utils.isAddress(proposer.address));

    const threadDeployer = await new ethers.Contract(
        process.env.THREAD_DEPLOYER,
        require('../../../artifacts/contracts/thread/ThreadDeployer.sol/ThreadDeployer.json').abi,
        proposer
    )

    const USD = process.env.USD;
    console.log(USD);
    
    
    const crowdfund = await CROWDFUND.utils.getCrowdfundedThread(threadDeployer, { id: "LAST", return: true, proposer: proposer })
    
    console.log(crowdfund.address)
    
    const state = await crowdfund.state();
    console.log("Symbol: ", await crowdfund.symbol())
    console.log("CrowdfundState == ", (state==0) ? "Active" : state);
    switch (state) {
        case 3:
            {
                console.log("Crowdfound Finished!!");
                process.exit(0)
            }
            
            break;
    
        default:
            break;
    }
    console.log("CrowdfundERC20:\t", await crowdfund.token() )
    console.log(ethers.utils.id("crowdfund!!!"));
    
    const frbc = await new ethers.Contract(process.env.FRBC,
        require('../../../artifacts/contracts/erc20/FrabricERC20.sol/FrabricERC20.json').abi,
        proposer
    )

    console.log(
        proposer.address,
        (await frbc.whitelisted(proposer.address)) ? 
            "Whitelisted" : "!!!NOT WHITELISTED!!!",
        "\nKYC: ",
        (await frbc.kyc(proposer.address)),
        "\nALLOWANCE: ",
        (await frbc.allowance(proposer.address, crowdfund.address))
    );
    const frbcAllowance = await frbc.allowance(proposer.address, crowdfund.address);
    
    const frabric = new ethers.Contract(process.env.INITIALFRABRIC,
        require("../../../artifacts/contracts/frabric/Frabric.sol/Frabric.json").abi,
        proposer
    )
    if(
        ethers.utils.isAddress(frabric.address) && frbcAllowance.eq(0)
    ) {
        const tx = await frbc.increaseAllowance(crowdfund.address, ethers.BigNumber.from(1000000000000));
        console.log(tx)
    }
    
    console.log(await frbc.owner())

    // Get simple ERC20 token ABI
    const erc20 = new ethers.Contract(process.env.USD,
        require("../../../artifacts/contracts/test/TestERC20.sol/TestERC20.json").abi,
        proposer
    )
    // Check for validity
    if(
        ethers.utils.isAddress(erc20.address)
    ) {
        console.log("SYMBOL: ", await erc20.symbol())
        // Check for allowance and approve if 0
        const erc20Allowance = async () => await erc20.allowance(proposer.address, crowdfund.address);
        console.log(await erc20Allowance());
        if((await erc20Allowance()).eq(0)) {
            const tx = await erc20.approve(crowdfund.address, ethers.BigNumber.from(1000000000000))
            console.log(tx)
            console.log(await erc20Allowance());

        }else {
            try {   
                // Check for balance, [Deposid, Execute]
                console.log("Depositor USD.balanceOf: ", await erc20.balanceOf(proposer.address))
                const txd = await crowdfund.deposit(ethers.BigNumber.from(10000), {gasLimit: 30000000});
                console.log("DEPOSIT \n", txd)
                const outstanding = await crowdfund.outstanding()
                console.log("Crowdfund.outstanding:\t", outstanding);
                const tx = await crowdfund.connect(signers[0]).execute();
                console.log(tx.hash)
                console.log("EXECUTED!!!");
            } catch (error) {
                console.log("----------------------- ERROR --------------------------")
                console.log("ERROR:\n", error);
                console.log("--------------------- END ERROR -------------------------")
            }        
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





// console.log(frabric.address);

