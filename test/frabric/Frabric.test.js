const { ethers, waffle, network } = require("hardhat");
const { MerkleTree } = require("merkletreejs");

const { assert, expect } = require("chai");

const deployTestFrabric = require("../../scripts/deployTestFrabric.js");
const { FrabricProposalType, ParticipantType, GovernorStatus, completeProposal } = require("../common.js");

let signers, deployer, kyc, genesis, governor;
let bond, threadDeployer;
let frbc, frabric, nextID;

describe("Frabric", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [deployer, kyc, genesis, governor] = signers.splice(0, 4);

    let {
      usdc: usdcAddress,
      bond: bondAddr, threadDeployer: threadDeployerAddr,
      frbc: frbcAddr, frabric: frabricAddr
    } = await deployTestFrabric();
    usdc = (await ethers.getContractFactory("TestERC20")).attach(usdcAddress).connect(deployer);
    bond = (await ethers.getContractFactory("Bond")).attach(bondAddr).connect(governor);
    threadDeployer = (await ethers.getContractFactory("ThreadDeployer")).attach(threadDeployerAddr).connect(governor);
    frbc = (await ethers.getContractFactory("FrabricERC20")).attach(frbcAddr).connect(genesis);
    frabric = (await ethers.getContractFactory("Frabric")).attach(frabricAddr).connect(genesis);

    nextID = 2;
  });

  it("should have the expected bond/threadDeployer", async () => {
    expect(await frabric.bond()).to.equal(bond.address);
    expect(await frabric.threadDeployer()).to.equal(threadDeployer.address);
  });

  it("shouldn't let anyone propose", async () => {
    assert(!(await frabric.canPropose(signers[1].address)));
  });

  it("shouldn't let you propose genesis participants", async () => {
    // TODO
  });

  it("should let you add KYC agencies", async () => {
    // TODO
  });

  it("should let you add participants", async () => {
    let signersIndex = 0;
    for (let pType of [ParticipantType.Individual, ParticipantType.Corporation]) {
      // Create the merkle tree of participants
      const merkle = new MerkleTree(
        [signers[signersIndex].address, signers[signersIndex + 1].address, signers[signersIndex + 2].address].map(
          (address) => address + "000000000000000000000000"
        ),
        ethers.utils.keccak256,
        { sortPairs: true }
      );

      // Perform the proposal
      const pID = nextID;
      nextID++;
      expect(
        await frabric.proposeParticipants(
          pType,
          merkle.getHexRoot(),
          ethers.utils.id("Proposing new participants")
        )
      )
        .to.emit("NewProposal").withArgs(
          pID,
          FrabricProposalType.Participants,
          genesis,
          ethers.utils.id("Proposing a new Thread")
        )
        .to.emit("ParticipantsProposed").withArgs(pID, pType, merkle.getHexRoot());
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
          participant: signers[signersIndex + 1].address,
          kycHash: ethers.utils.id("Signer " + (signersIndex + 1))
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
      expect(
        await frabric.approve(
          pID,
          signArgs[2].participant,
          signArgs[2].kycHash,
          merkle.getHexProof(signArgs[2].participant + "000000000000000000000000"),
          signature
        )
      ).to.emit("ParticipantChange").withArgs(signArgs[2].participant, pType);

      // Verify they were successfully added
      expect(await frbc.info(signers[signersIndex + 1].address)).to.equal(signArgs[2].kycHash);
      expect(await frabric.participant(signers[signersIndex + 1].address)).to.equal(pType);
      assert(await frabric.canPropose(signers[signersIndex + 1].address));
      signersIndex += 3;
    }
  });

  it("should let you add a governor", async () => {
    const pID = nextID;
    nextID++;
    expect(
      await frabric.proposeParticipants(
        ParticipantType.Governor,
        governor.address + "000000000000000000000000",
        ethers.utils.id("Proposing a new governor")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        FrabricProposalType.Participants,
        genesis,
        ethers.utils.id("Proposing a new governor")
      )
      .to.emit("ParticipantsProposed").withArgs(pID, ParticipantType.Governor, governor.address + "000000000000000000000000");
    await completeProposal(frabric, pID);
    expect(await frabric.governor(governor.address)).to.equal(GovernorStatus.Unverified);

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
        participant: governor.address,
        kycHash: ethers.utils.id("Governor")
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
    expect(
      await frabric.approve(
        pID,
        signArgs[2].participant,
        signArgs[2].kycHash,
        [],
        signature
      )
    ).to.emit("ParticipantChange").withArgs(signArgs[2].participant, ParticipantType.Governor);

    // Verify they were successfully added
    expect(await frbc.info(governor.address)).to.equal(signArgs[2].kycHash);
    expect(await frabric.participant(governor.address)).to.equal(ParticipantType.Governor);
    assert(await frabric.canPropose(governor.address));
  });

  it("should let you remove bond", async () => {
    // TODO
  });

  it("should let you slash bond", async () => {
    // TODO
  });

  it("should let you create a Thread", async () => {
    const descriptor = "0x" + (new Buffer.from("ipfs").toString("hex")).repeat(8);
    const data = (new ethers.utils.AbiCoder()).encode(
      ["address", "uint256"],
      [usdc.address, 1000]
    );
    const pID = nextID;
    nextID++;
    expect(
      await frabric.proposeThread(
        0,
        "Test Thread",
        "TTHR",
        descriptor,
        governor.address,
        data,
        ethers.utils.id("Proposing a new Thread")
      )
    )
      .to.emit("NewProposal").withArgs(
        pID,
        FrabricProposalType.Thread,
        genesis,
        ethers.utils.id("Proposing a new Thread")
      )
      .to.emit("ThreadProposed").withArgs(
        pID,
        0,
        governor.address,
        "Test Thread",
        "THREAD",
        descriptor,
        data
      );

    const tx = await completeProposal(frabric, pID);
    const thread = (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.thread;
    expect(tx)
      .to.emit("Thread").withArgs(thread, 0, governor.address, null, descriptor)
      .to.emit("CrowdfundedThread").withArgs(thread, usdc.address, null, 1000);
  });

  it("should let you create a proposal on a Thread", async () => {
    // TODO
  });

  it("should correctly handle participant removals", async () => {
    // TODO
  });
});
