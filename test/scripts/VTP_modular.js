const hre = require("hardhat");
const { ethers, upgrades, waffle  } = hre;
const { expect } = require("chai");

const genesis = require("../../genesis.json");
const { ProposalState, CommonProposalType, VoteDirection } = require("../common.js")

// Networks
const networks = {
    rinkeby: 4,
    goerli: 5
};
// Contract addresses
const FRABRIC = {
    beaconProxy: "0xBeb2BB398dA981Ec4C9dC5825158382eb4337CDa",
    singleBeacon: "0xAe371F948d46399E920104575BAE1D186D8B2642"
};

// Wallet primitive and Signers
const WALLETS = (process.env.WALLETS).split(",");

/**
 * @dev TODO:
 *      - Fix Queue and Complete sequence for all case scenario 
 *      - Inject contractObject into the Proposal Object at "constructor" [V]
 *      - Saperate Vote, Queue and Complete into function [V]
 *      - Re-write "triggerUpgrade sequence with new format"  
 *      - Modularize script for better usage [V]
 */


//Proposal
class Proposal {
    constructor(id, contract) {
        this.contract = contract
        this.id = ethers.BigNumber.from(id);
        this.state = 0
        this.block = 0;
        this.type = -1
        this.startTimeStamp = 0;
        this.endTimeStamp = 0;
    }
    getData = async () => {
        const events = await (await this.contract.queryFilter(this.contract.filters.Proposal()))
        events.forEach(event => {
            if(event.args.id.eq(this.id)) {
                this.block = event.blockNumber
                this.type = event.args.proposalType
            }    
        });let tx
        if(this.block == 0) {
            console.error("Proposal Not Found!!");
            process.exit(1);
        }
    };
    checkSigner = async (signer) => {
        let isGenesis;
        isGenesis = await this.contract.callStatic.canPropose(signer.address)
            console.log("Wallet: " + signer.address +(isGenesis ?  " is verified" : " is NOT verified"));
    };
    checkSigners = async (...signers) => {
        console.log(signer.map( sig => {
            return sig.address
        }));
        let isGenesis;
        signers.forEach( async( signer, i ) => {
            isGenesis = await this.contract.callStatic.canPropose(signer.address)
            console.log("Wallet: " + signer.address +(isGenesis ?  " is verified" : " is NOT verified"));
        });
    };
    getState = async () => {
        const propStates = (await this.contract.queryFilter(this.contract.filters.ProposalStateChange()));
        propStates.forEach(prop => {
            if(prop.args.id.eq(this.id)){
                this.state = prop.args.state
            }
        });
    };
    printState = () => {
        const states = Object.keys(ProposalState)
        return states[this.state];
    };
    printData = () => {
        return {
            id: this.id.toNumber(),
            type: this.type.toNumber(),
            state: [this.state, this.printState()],
            startTimeStamp: this.startTimeStamp,
            endTimestamp: this.endTimeStamp
        }
    };
    // vote = async (contract, voter) => {        
    //     return new Promise( 
    //         resolve => {
    //             console.log("BEFORE VOTE");
    //             let x = contract.connect(voter).vote([this.id], [ethers.constants.MaxUint256.mask(111)])
    //             if (x) {
    //                 console.log("X"infura" X");
    //                 resolve(x)
    //             }
    //         }    
    //     ); 
    // };
    queue = async () => {
        const tx = await this.contract.queueProposal(this.id);
        (await( expect(tx).to.emit(this.contract, "ProposalStateChange").withArgs(this.id, ProposalState.Queued))) 
            ? console.log("ProposalQueued") : console.log("Still Active");
        return new Promise(res => {
            if( tx.status){
                res(tx)
            }
        })
    };
    complete = async () => {
        const data = "0x"
        const tx2 = await this.contract.completeProposal(this.id, data);
        const isCompleted = (await expect(tx2).emit(this.contract, "ProposalStateChange").withArgs(this.id, ProposalState.Executed))
        return isCompleted
    };
}



const utils =  {
    getProposalState: async (contract, id) => {
        const propStates = await (await contract.queryFilter(contract.filters.ProposalStateChange()))
        let proposalStateData
        propStates.forEach(prop => {
            if(prop.args.id.eq(id)){
                proposalStateData = {
                    state: prop.args.state,
                    block: prop.blockNumber
                }
            }
        })
        console.log(proposalStateData);
        return proposalStateData;
    },
    getTimeStampFromBlock: async (provider, blockNumber) => {
        return provider.getBlock(blockNumber).then((block) => {
            let x = block.timestamp;
            return block.timestamp;
        });
    
    },
    voteWithSigners: (proposal, signers) => {
        /**
     * VOTE ON PROPOSAL
     */    
         let votes = signers.map( (voter) => {
            return (new Promise(resolve => {
                resolve (proposal.contract.connect(voter).vote([proposal.id], [ethers.constants.MaxUint256.mask(111)]))
            }))
        })
        var results = Promise.all(votes);
        results.then( VOTES => {
           console.log(VOTES.map(vote => {
            return {
                hash: vote.hash,
                event: expect(vote).to.emit(proposal.contract, "Vote") ? true : false
            }
           }));

        })
    },
    walletSetup: (provider) => {
        let _signers = [];
        WALLETS.forEach( ( wallet,i ) => {
            _signers.push(new ethers.Wallet(wallet, provider))
            console.log(_signers[i].address);
        });
        return _signers
    },
    now: () => { 
        return (new Date().getTime() / 1000);
    },
    t : (endTimeStamp) => { 
        return (endTimeStamp - utils.now());
    },
    sleep: async (ms) => {
        return new Promise(resolve => setTimeout(resolve, ms));
     }
}

// const queueProposal = async (contract, id) => {
//     let tx
//     await contract.queueProposal(id).then((tx) => {
//         (await( expect(tx).to.emit(contract, "ProposalStateChange").withArgs(id, ProposalState.Queued))) 
//             ? console.log("ProposalQueued") : "Still Active";
//     })
// }

// const completeProposal = async (contract, id) => {
//     const data = "0x"
//     const tx2 = await contract.completeProposal(id, data);
//     const isCompleted = (await expect(tx2).emit(contract, "ProposalStateChange").withArgs(id, ProposalState.Executed))
//     isCompleted ? console.log("Proposal Completed") : console.log("Something went wrong on Complete");
// };




module.exports.setup = async (id, config) => {

    const signers = config.signers;

    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    console.log("Vote to Complete");

    // waitingPeriod constant
    let waitingPeriod = {
        voting: 600,
        queue:  10,
        lapse:  36000
    };

/**
 * LOAD CONTRACTS
 * @dev beaconProxy as Frabric even tho might be InitialFrabric 
 *      which has limited ABI, will make it easier to reuse the code
 */
    const frabric = await new ethers.Contract(
        config.beaconProxy,
        require('../../artifacts/contracts/frabric/Frabric.sol/Frabric.json').abi,
        signers[0]
    );
    
    // get WaitingPeriods from the contract
    waitingPeriod.voting = (await frabric.votingPeriod()).toNumber();
    waitingPeriod.queue = (await frabric.queuePeriod()).toNumber();
    waitingPeriod.lapse = (await frabric.lapsePeriod()).toNumber();
    console.log(waitingPeriod);
    
/**
 * ######## PROPOSAL SETUP ###########
 */
    let proposal = new Proposal(id, frabric);   
    await proposal.getData(frabric).then( () => {
        console.log(proposal.printData());
    })
    signers.forEach( async (signer) => {
        await proposal.checkSigner(frabric, signer);
    })
    
    
    proposal.startTimeStamp = (await utils.getTimeStampFromBlock(config.provider, proposal.block));
    proposal.endTimeStamp = proposal.startTimeStamp + waitingPeriod.voting
    console.log(proposal.printData());        
    
    await proposal.getState(frabric);
    console.log(proposal.printData());
    const t = () => { return utils.t(proposal.endTimeStamp)}

    console.log("T == ", t());
    
    return {
        proposal: proposal,
        waitingPeriod: waitingPeriod
    }
    
    /**
     * VOTE ON PROPOSAL
     */    
        // let votes = signers.map( (voter) => {
        //     return (new Promise(resolve => {
        //         resolve (frabric.connect(voter).vote([proposal.id], [ethers.constants.MaxUint256.mask(111)]))
        //     }))
        // })
        // var results = Promise.all(votes);
        // results.then( VOTES => {
        //    console.log(VOTES.map(vote => {
        //     return {
        //         hash: vote.hash,
        //         event: expect(vote).to.emit(frabric, "Vote") ? true : false
        //     }
        //    }));
        // })
        // utils.voteWithSigners(proposal, signers
    

    
}

/***
 * @dev Transitrory function to allow for diffs in setups and module calls
 */
const callModule = (async (id, config) => { 
    console.log(config);

     /**
    * SETUP PROVIDER AND SIGNERS
    */
    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider);
  
    signers ? console.log("SignersReady"): console.log("signers not ready");
    console.log(signers.map( signer => { return signer.address }));
      
    // add provider and signers to the config
    config.provider = provider;
    config.signers = signers;


    const {proposal, waitingPeriod } = await module.exports.setup(id, config)
    const t = () => { return utils.t(proposal.endTimeStamp) }
    
    
    if(t() >= 0) {
        console.log("[V] Voting period!");
        utils.voteWithSigners(proposal, signers)


    if( (t() < 0) ) {
        if(proposal.state == ProposalState.Active){
            console.log("Queueing");
            await proposal.queue()
        }
        if(proposal.state == ProposalState.Queued){
            console.log("Completing");
            utils.sleep(waitingPeriod.queue *1000).then(
                async () => {
                    await proposal.complete().then( () => { console.log("Proposal Completed");})
                }
            )
        }
        
    }
            
            
        
    }
            
})




/**
 * COMMAND LINE CALL
 */
if (require.main === module) {
    /***
     *  CONFIG OBJ SETUP
     */
    const CONFIG = {
        network:        networks.goerli,
        beaconProxy:    FRABRIC.beaconProxy,
        singleBeacon:   FRABRIC.singleBeacon,
    }
    /***
     * PROPOSAL ID
     */
    const ID = 0x22
    callModule( ID, CONFIG ) 
}

exports.proposalUtils = utils;
exports.Proposal = Proposal