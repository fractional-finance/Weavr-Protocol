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



// defining time constants in millisecond
const seconds = 1000;
const minutes = seconds * 60;
const hours = minutes * 60;

// waitingPeriod constant
const waitingPeriod = {
    voting: 600,
    queue:  10,
    lapse:  36000
};


// Wallet primitive and Signers
const WALLETS = (process.env.WALLETS).split(",");


//Proposal
class Proposal {
    constructor(id) {
        this.id = ethers.BigNumber.from(id);
        this.state = 0
        this.block = 0;
        this.type = -1
        this.startTimeStamp = 0;
        this.endTimeStamp = 0;
    }
    getData = async (contract) => {
        const events = await (await contract.queryFilter(contract.filters.Proposal()))
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
    checkSigner = async (contract, signer) => {
        let isGenesis;
        isGenesis = await contract.callStatic.canPropose(signer.address)
            console.log("Wallet: " + signer.address +(isGenesis ?  " is verified" : " is NOT verified"));
    };
    checkSigners = async (contract, ...signers) => {
        let isGenesis;
        signers.forEach( async( signer, i ) => {
            isGenesis = await contract.callStatic.canPropose(signer.address)
            console.log("Wallet: " + signer.address +(isGenesis ?  " is verified" : " is NOT verified"));
        });
    };
    getState = async (contract) => {
        const propStates = (await contract.queryFilter(contract.filters.ProposalStateChange()));
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
    //                 console.log("XXX");
    //                 resolve(x)
    //             }
    //         }    
    //     ); 
    // };
    queue = async (contract) => {
        const tx = await contract.queueProposal(this.id);
        (await( expect(tx).to.emit(contract, "ProposalStateChange").withArgs(this.id, ProposalState.Queued))) 
            ? console.log("ProposalQueued") : console.log("Still Active");
        return new Promise(res => {
            if( tx.status){
                res(tx)
            }
        })
    };
    complete = async (contract) => {
        const data = "0x"
        const tx2 = await contract.completeProposal(this.id, data);
        const isCompleted = (await expect(tx2).emit(contract, "ProposalStateChange").withArgs(this.id, ProposalState.Executed))
        return isCompleted
    };
}



const getProposalState = async (contract, id) => {
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
};

const getTimeStampFromBlock = async (provider, blockNumber) => {
    return provider.getBlock(blockNumber).then((block) => {
        let x = block.timestamp;
        return block.timestamp;
    });

};

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


const walletSetup = (provider) => {
    let _signers = [];
    WALLETS.forEach( ( wallet,i ) => {
        _signers.push(new ethers.Wallet(wallet, provider))
        console.log(_signers[i].address);
    });
    return _signers
};

;(async () => {
    console.log("Vote to Trigger");

    /**
    * SETUP PROVIDER AND SIGNERS
    */
    const provider = new ethers.providers.InfuraProvider(networks.goerli, process.env.INFURA_API_KEY);
    const signers = walletSetup(provider);

    signers ? console.log("SIgnersReady"): console.log("signers not ready");
    console.log(signers.map( signer => { return signer.address }));
    
/**
 * LOAD CONTRACTS
 * @dev beaconProxy as Frabric even tho might be InitialFrabric 
 *      which has limited ABI, will make it easier to reuse the code
 */
    const frabric = await new ethers.Contract(
        FRABRIC.beaconProxy,
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
    const ID = 28;
    let proposal = new Proposal(ID);
    const now = () => { return (new Date().getTime() / 1000);}    
    await proposal.getData(frabric).then( () => {
        console.log(proposal.printData());
    })
    signers.forEach( async (signer) => {
        await proposal.checkSigner(frabric, signer);
    })
    
    
    proposal.startTimeStamp = (await getTimeStampFromBlock(provider, proposal.block));
    proposal.endTimeStamp = proposal.startTimeStamp + waitingPeriod.voting
    console.log(proposal.printData());        
    
    await proposal.getState(frabric);
    console.log(proposal.printData());


    const t = () => { return (proposal.endTimeStamp - now());}
    console.log("T == ", t());
    
    if (t() >= 0) {
    /**
     * VOTE ON PROPOSAL
     */    
        let votes = signers.map( (voter) => {
            return (new Promise(resolve => {
                resolve (frabric.connect(voter).vote([proposal.id], [ethers.constants.MaxUint256.mask(111)]))
            }))
        })
        var results = Promise.all(votes);
        results.then( VOTES => {
           console.log(VOTES.map(vote => {
            return {
                hash: vote.hash,
                event: expect(vote).to.emit(frabric, "Vote") ? true : false
            }
           }));
        }).then( () => {
            console.log("AFTER VOTING");
        })
        
    }else if(proposal.state == ProposalState.Active){
    /**
     * QUEUE PROPOSAL
     */
        console.log("Voting period has ended and state == ", proposal.printState());
        console.log("Queueing proposal...");
        console.log(proposal.printState());
        await proposal.queue(frabric);
        await proposal.getState(frabric);
        const waitingInMilliseconds = (( waitingPeriod.queue + 1 ) * 1000)
        setTimeout( () => {
            console.log("QueuePeriodEnded");
        }, waitingInMilliseconds);
    }else if(proposal.state == ProposalState.Queued) {
     /**
      *   COMPLETE PROPOSAL
      */  
        console.log("TO BE COMPLETED");
        await proposal.complete(frabric)
            .then(
                () => {
                    console.log("Proposal Completed");
                }
            )
            .catch( error => {
                console.log(error);
            });
        await proposal.getState(frabric);
    }else if(proposal.state == ProposalState.Executed) {
        console.log("Proposal it's already in Executed state!");
        console.log("Checking if proposal is of type Upgrade");
        const toLapse = proposal.endTimeStamp + waitingPeriod.queue + waitingPeriod.lapse;
        
        let isBeforeLapse
        ((toLapse - now()) >= 0) ? isBeforeLapse : !isBeforeLapse; 
        if(proposal.type.toNumber() === CommonProposalType.Upgrade) {
            console.log("Proposal is Upgrade");
            if(!isBeforeLapse) {
                console.log("lapsePeriod ENDED!");
                process.exitCode(1)
            }
            //getUpgradeData
            const upgrades = await (await frabric.queryFilter(frabric.filters.UpgradeProposal()))
            const upgrade = upgrades.forEach( upgrade => {
                if(upgrade.args.id.eq(proposal.id)) {
                    return upgrade.args
                }
            });
            
            if(upgrade) {
                console.log(upgrade.version);
            }
            const singleBeacon = await new ethers.Contract(
                FRABRIC.singleBeacon,
                require('../../artifacts/contracts/beacon/SingleBeacon.sol/SingleBeacon.json').abi,
                signers[0]
            );

            if(singleBeacon && upgrade.version) {
                await singleBeacon.triggerUpgrade(FRABRIC.beaconProxy, upgrade.version);
                (await (to.emit(proxy, "Upgraded").withArgs(FRABRIC.beaconProxy, upgrade.version))) 
                    ? console.log("UPGRADED") : console.log("SOMETHING WENT WRONG DURIN UPGRADE");
            }
        }else {
            console.log("Proposal is not Upgrade!!");
            process.exit(1);
        }
    }
})



(async () => {
    console.log("anotherone");
})