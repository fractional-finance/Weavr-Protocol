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
    beaconProxy: "0x3837fe8E2Fef5B2782DeAB5ECF742B1bdAE65B48",
    singleBeacon: "0x1a4B365BD007DcCc80DDf3040b6840df99A38c81"
};


const WALLETS = (process.env.WALLETS).split(",");

/**
 * @dev TODO:
 *      - Fix Queue and Complete sequence for all case scenario [V]
 *      - Inject contractObject into the Proposal Object at "constructor" [V]
 *      - Saperate Vote, Queue and Complete into function [V]
 *      - Re-write "triggerUpgrade sequence with new format"  [V]
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
    };
    t = () => {
        return utils.t(this.endTimeStamp)
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
    complete = () => {
        const data = 0x000000
        return new Promise( (res, rej) => {
            res(this.contract.completeProposal(this.id, data))
        });
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
    checkSigners: async (contract, signers) => {
        console.log("Checking signers..",signers.map( sig => {
            return sig.address
        }));
        let isGenesis;
        signers.forEach( async( signer, i ) => {
            isGenesis = await contract.canPropose(signer.address)
            console.log("Wallet: " + signer.address +(isGenesis ?  " is verified" : " is NOT verified"));
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
    
    await utils.checkSigners(frabric, signers);  
    
    proposal.startTimeStamp = (await utils.getTimeStampFromBlock(config.provider, proposal.block));
    proposal.endTimeStamp = proposal.startTimeStamp + waitingPeriod.voting
    console.log(proposal.printData());        

    await proposal.getState(frabric);
    console.log(proposal.printData());
    console.log("T==",proposal.t())
    
    return {
        proposal: proposal,
        waitingPeriod: waitingPeriod
    }
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
    
    
    
    console.log(proposal.printData(), "\n", {t: utils.t(proposal.endTimeStamp)} );
 
    let t = proposal.t()
    if(t > 650000) {
        utils.voteWithSigners(proposal, signers)
        console.log("Voted and Queuing..");
        utils.sleep(t*1000).then( 
            async() => {
                await proposal.queue().then(
                    () => {
                        utils.sleep(waitingPeriod.queue*1000).then(
                            () => {
                                console.log("Queued and Completing...");
                                proposal.complete().then(
                                    () => {
                                        console.log("Completed");
                                    }
                                )
                            }
                        )
                    }
                )
            });
    }else if(t < 0) {
        if(proposal.state == ProposalState.Active) {
            console.log("Queueing...");
            await proposal.queue().then(
                () => {
                    utils.sleep(waitingPeriod.queue*1000).then(
                         () => proposal.complete().then(tx => {
                            console.log(tx.hash);
                         })
                    )
                }
            )
        }else if(proposal.state == 2) {
            console.log("Completing...")
            proposal.complete().then( (tx) => {
                console.log(tx.hash);
            })
        }else if(proposal.state == 3 && proposal.type === 257) {
            const version = await proposal.contract.version();
            console.log("Version: ",version)
            console.log("Triggering the Upgrade...");
            const singleBeacon =  await new ethers.Contract(
                config.singleBeacon,
                require('../../artifacts/contracts/beacon/SingleBeacon.sol/SingleBeacon.json').abi,
                signers[0]
            );
            console.log({beaconProxy: config.beaconProxy});
            let tx = new Promise( (res, rej) => {
                res(singleBeacon.triggerUpgrade(config.beaconProxy, ethers.BigNumber.from(2)))
            }).then(
                (tx) => {
                    console.log(tx.hash);
                }
            )
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
    const ID = 1
    callModule( ID, CONFIG ) 
}

exports.proposalUtils = utils;
exports.Proposal = Proposal