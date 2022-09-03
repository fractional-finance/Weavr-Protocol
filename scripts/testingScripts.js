const { Provider } = require('@ethersproject/abstract-provider')
const { ethers, waffle, network } = require('hardhat')


const u2SDK = require("@uniswap/v2-sdk");
const uSDK = require("@uniswap/sdk-core");

const FrabricERC20 = require("./deployFrabricERC20.js");
const deployFrabric = require("./deployFrabric")

const BEACON_PROXY = "0x0a33105b722ae9adc0def09e556c4ef24f812b9d"


/**
{
  proxy:    '0x3474c71a1d794a315085e51d09e5945258383df9',
  instance: '0xf1Ba6Bf73c4EB490CC8389B138137886d22bA3Ed',
  version:   2,
  code:     '0x95ffe75f4499C247B56433BB132B20Aa6B6023a0',
  data:     '0x00000000000000000000000072f61f5451c31d8ea61ce8bf84893234d08c89fe0000000000000000000000004b697e05bd238819196653ac71fd869c140dbee7000000000000000000000000403383c411c0eb14ea0bd15e7c2ad5431a7410c2',
  info:     '0x5673bfd4525158351f648ff258d0ea919b3da8bbbb2a0f87cfe021d4045587c0'
}
 */
/**
 * Thread Deployer: 0x7a8a5d3eE2382E7648cb329353C53ae17b04A1c3
Bond:            0xB1676e099FEe26D50a3dCd799958Ce8ef99A33e2
Frabric Code:    0x0A43181B5f523683Ee4fa7baC0a3f89647475A47
 */

/**
Auction:         0x45D65375d36DB9007653ac17C0522ed286543E39
ERC20 Beacon:    0x670e4084A17bF32e4BBaD4082CdfA4FF46251B60
FRBC:            0xF4546E3688bd31434f24E6795a3DBB873B4B85C9
FRBC-USD Pair:   0xB24d33d333acA6778C5CbB074875A70481CB351D
Initial Frabric: 0x6F97010e5D930943e926E7125ec4E7769b7c934c
DEX Router:      0xB9176F50942cF57BCDFa597199c0B090Bfc86F0c
*/
const INITIAL_FRABRIC_ADDRESSES = {
  auction:        "0x02e46D3941ff0b051D74465a376899e0a0611d50",
  erc20Beacon:    "0x4C89d0e6BA9E82402b0979D89Cde054028346645",
  frbc:           "0x1Db4963c79C431D71e083d114AC5b79fdE3e808e",
  frbcUsdPair:    "0x89A9fCe94799871A2E2a5EEd7df57877e7AcDC2C",
  initialFrabric: "0xf1Ba6Bf73c4EB490CC8389B138137886d22bA3Ed",
  dexRouter:      "0xf66576C510b924910450dFf1107bC990BE8b2611",
}

/**
Thread Deployer: 0x4B697e05Bd238819196653ac71fd869c140dbEe7
Bond:            0x72f61F5451c31d8eA61ce8BF84893234D08C89FE
Frabric Code:    0x95ffe75f4499C247B56433BB132B20Aa6B6023a0
*/
const FRABRIC = {
  threadDeployer: "0x4B697e05Bd238819196653ac71fd869c140dbEe7",
  bond:           "0x72f61F5451c31d8eA61ce8BF84893234D08C89FE",
  frabricCode:    "0x95ffe75f4499C247B56433BB132B20Aa6B6023a0"
}

const USD = "0x2f3A40A3db8a7e3D09B0adfEfbCe4f6F81927557"

const {
  CommonProposalType,
  FrabricProposalType,
  ThreadProposalType,
  ParticipantType,
  GovernorStatus,
  proposal,
  queueAndComplete,
  propose
} = require("../test/common.js");
const { constants } = require('ethers');
const deployInitialFrabric = require('./deployInitialFrabric.js');

let signGlobal = [
  {
    name: 'Frabric Protocol',
    version: '2',
    chainId: 4,
    verifyingContract: BEACON_PROXY
  },
  {
    Vouch: [{ type: 'address', name: 'participant' }],
    KYCVerification: [
      { type: 'uint8', name: 'participantType' },
      { type: 'address', name: 'participant' },
      { type: 'bytes32', name: 'kyc' },
      { type: 'uint256', name: 'nonce' },
    ],
  },
]

function sign(signer, data) {
  let signArgs = JSON.parse(JSON.stringify(signGlobal))
  if (Object.keys(data).length === 1) {
    console.log("### VOUCHING ###", data);
    signArgs[1] = { Vouch: signArgs[1].Vouch }
  } else {
    signArgs[1] = { KYCVerification: signArgs[1].KYCVerification }
  }

  // Shim for the fact ethers.js will change this functions names in the future
  if (signer.signTypedData) {
    return signer.signTypedData(...signArgs, data)
  } else {
    return signer._signTypedData(...signArgs, data)
  }
}

async function getFrabricERC20Contract(signer) {
  let contract
  if(signer){
    contract = await new ethers.Contract(
      "0xc9DE6D792a8C6410E15744b47C478820013f0312",
      require('../artifacts/contracts/erc20/FrabricERC20.sol/FrabricERC20.json').abi,
      signer
    )
    return contract
  }else{
    contract = null
  }

  return contract
}

async function proposeThread(frabric, users) {
  let [signer, governor] = users
  if(frabric && signer.address && governor.address && (await frabric.canPropose(signer.address))){
    
  }else {
    console.log("something went wrong during params check in the `proposeThread` function!")
  }
}

function genesis() {
  jsonList = require('../genesis.json')
  return jsonList
  
}


async function deployInitialFrabricGoerli() {
  console.log(genesis());
}

async function proposeUpgradeToTestFrabric(frabric, payload) {
  
  // PRINT GENESIS ADDRESSES
  const events = await frabric.queryFilter(frabric.filters.ParticipantChange());
  for (let i in events) {
    if(events[i].args.participantType == ParticipantType.Genesis) {
      console.log( "GENESIS :: ", events[i].args.participant)
    }
  }
  let ei = events.length - 1
  console.log(events[ei].args);
  
  /** 
   * 1.
   **/
   const signer = payload.signer
  
  /**
   * DEPLOY NEW FRABRIC CONTRACTS
   */
  // let upgrade
  // upgrade = (await deployFrabric(add.auction, add.erc20Beacon, USD, add.frbcUsdPair, add.initialFrabric))
  // console.log(upgrade)
  
  /**
   * GET THE DATA ENCODED VAR READY
   */
  const DATA = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "address"],
    [FRABRIC.bond, FRABRIC.threadDeployer, signer.address]
  )

  /**
   * CALCULATE PAYLOAD FOR TESTING PORPUSES
   */
  const PAYLOAD = {
    proxy: "0xf1Ba6Bf73c4EB490CC8389B138137886d22bA3Ed",
    instance: "0x18a5aa5d22a9794141fd64734feee06e2df5978f",
    version: ethers.BigNumber.from(2),
    code: FRABRIC.frabricCode,
    data: DATA,
    info: ethers.utils.id("This is a frabric upgrade"),
  } 
  console.log(PAYLOAD);


  /**
   * CALL THE SMARTCONTRACT FUNCTION
   */
  let newFrabricTX
    try {
      newFrabricTX = await (await frabric.proposeUpgrade(
        PAYLOAD.proxy,
        PAYLOAD.instance,
        PAYLOAD.version,
        PAYLOAD.code,
        PAYLOAD.data,
        PAYLOAD.info,
        {
          gasLimit: 3000000,
          gasPrice:30
        }
      ))
    }catch (err) {
      console.log(err);
    }

    if(newFrabricTX){
      console.log("Printing NEW_FRABRIC");
      console.log(newFrabricTX);
    }

}

async function queueProposal(frabric, signer, proposal) {
  let tx
  if(frabric && signer.address && (await frabric.canPropose(signer.address))){
    tx = (await frabric.
              queueProposal(
                ethers.BigNumber.from(proposal),
                {
                  gasLimit: 300000
                }))
  }else {
    console.log("something went wrong during params check in the `queueProposal` function!")
  }
  return tx
}

async function proposeGovernor(frabric, users) {
  let [signer, participant] = users
  let tx = false
  console.log(signer.address);
  if(frabric && signer && participant){
    let info = ethers.utils.id("Proposing " + participant.address, " as a Governor")
    tx = (await frabric.proposeParticipant(ParticipantType.Governor, participant, info, {gasLimit: 300000}))
  }else {
    console.log("something went wrong during params's check in the `proposeGovernor` function!")
  }

  return tx
}

async function getIFrabricERC20Interface(signer) {
  let contract
  if(signer){
    const ABI = require("../artifacts/contracts/interfaces/erc20/IFrabricERC20.sol/IFrabricERC20.json").abi
    let interface = await new ethers.utils.Interface(ABI)
    console.log(interface.getFunction("hasKYC"))
    return contract
  }else{
    contract = null
  }

  return contract
}


;(async () => {
  
  /**
   * SETUP PROVIDER AND SIGNER
   */
  const provider = new ethers.providers.InfuraProvider(5, process.env.INFURA_API_KEY)
  const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider)
  
  const participant = '0x404A9Ab87f0C51245FAc908cdcDa9f67F08Df980'
  
  /**
   * SIGNEWR CHECK
   */
  console.log("ADDRESS: ", signer.address);
  
  // deployInitialFrabricGoerli()


  /**
   * FRABIC INSTANCE SETUP WITH SIGNER
   */
  const frabric = await new ethers.Contract(
    INITIAL_FRABRIC_ADDRESSES.initialFrabric,
    require('../artifacts/contracts/frabric/InitialFrabric.sol/InitialFrabric.json').abi,
    signer
  )
  

  /**
   * GET SIGNATURE
   */
  // const signature = await sign(frabric.signer, {
  //   participant: participant,
  // })
  // console.log(signature);
  
  /**
   * SIGNER canPropose CHECK
   */
  let canProp = (await frabric.canPropose(signer.address))
  console.log(canProp ? signer.address + " can Propose": signer.address + " cannot Propose");


  /**
   * UPGRADE TO FRABRIC
   */
  await proposeUpgradeToTestFrabric(frabric, {signer: signer})


  /**
   * QUEUE PROPOSAL
   */
  // let queueTX = (await queueProposal(frabric, signer, 8))
  // console.log(queueTX);
  
  // let canComplete = (await frabric.completeProposal(
  //   8, 
  //   "0xd33c0e35cffe0cb3906c53494fb15ce1a049eb20a1cfcfcf7bb304ca88141a685cd3e356af3b2fe0fed01aa428a5b6908eb2bd1b6ca9aead361cd4eeac1fc6571b",
  //   {const events = await frabric.queryFilter(frabric.filters.ParticipantChange());
  // let erc20
  // try {
  //   erc20 = await FrabricERC20.deployFRBC(process.env.USD)  
  //   console.log(erc20);
  // } catch (error) {
  //   console.log(error.message);
  // }
  
  
  // let frabricERC20 = await getFrabricERC20Contract(signer)
  // if(frabricERC20){
  //   const tx = (await frabricERC20.callStatic.hasKYC(signer.address))
  //   console.log(tx ? "HAS KYC" : "NOT KYC");
    
    // ###### PROPOSE KYC #####
    // if(tx){
    //  let KYCProp = (await frabric.proposeParticipant(ParticipantType.KYC, participant, ethers.utils.id("Proposing Zerix for testing porpuses")))
    //  console.log(KYCProp);
    // }const events = await frabric.queryFilter(frabric.filters.ParticipantChange());

  // }else{
  //   console.log("CONTRACT NOT INITIALIZED")
  //   return
  // }
  // (await frabricERC20.callStatic.hasKYC(signer.address))
  // const tx = (await frabric.callStatic.vouch(
  //   '0x4C3D84E96EB3c7dEB30e136f5150f0D4b58C7bdB',
  //   signature,
  //   {
  //     gasLimit: 5000000
  //   }
  // ))
  // await tx.wait()
  // console.log(tx);
})()