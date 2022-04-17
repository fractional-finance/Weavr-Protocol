const { ethers, waffle, network } = require("hardhat");
const { MerkleTree } = require("merkletreejs");

const { assert } = require("chai");

const deployTestFrabric = require("../scripts/deployTestFrabric.js");
const { ParticipantType, completeProposal } = require("./common.js");

let signers, kyc, genesis, frabric, pID;

describe("Frabric", accounts => {
  before("", async () => {
    signers = await ethers.getSigners();
    [_, kyc, genesis] = signers.splice(0, 3);

    let { frabric: frabricAddr } = await deployTestFrabric();
    frabric = new ethers.Contract(
      frabricAddr,
      require("../artifacts/contracts/frabric/Frabric.sol/Frabric.json").abi,
      genesis
    );

    pID = 2;
  });

  it("should let you add participants", async () => {
    // Create the merkle tree of participants
    const merkle = new MerkleTree(
      [signers[0].address, signers[1].address, signers[2].address],
      ethers.utils.keccak256,
      { hashLeaves: true, sortPairs: true }
    );

    // Perform the proposal
    await frabric.proposeParticipants(ParticipantType.Individual, merkle.getHexRoot(), ethers.utils.id("Proposing new participants"));
    await completeProposal(frabric, pID);

    const signArgs = [
      {
        name: "Frabric Protocol",
        version: "1",
        chainId: 31337,
        verifyingContract: frabric.address
      },
      {
        KYCVerification: [
          { name: "participant", type: "address" },
          { name: "kycHash", type: "bytes32" }
        ]
      },
      {
        participant: signers[1].address,
        kycHash: "0x0000000000000000000000000000000000000000000000000000000000000003"
      }
    ];
    // Shim for the fact ethers.js will change this functions names in the future
    let signature;
    if (kyc.signTypedData) {
      signature = await kyc.signTypedData(...signArgs);
    } else {
      signature = await kyc._signTypedData(...signArgs);
    }

    // Approve the participant
    await frabric.approve(
      pID,
      signers[1].address,
      "0x0000000000000000000000000000000000000000000000000000000000000003",
      merkle.getHexProof(ethers.utils.keccak256(signers[1].address)),
      signature
    );
    pID++;

    // Verify they were successfully added
    assert.equal(await frabric.participant(signers[1].address), ParticipantType.Individual);
  });
});
