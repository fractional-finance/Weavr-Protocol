const { ethers, waffle, network } = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const { assert, expect } = require("chai");

const deployTestFrabric = require("../scripts/deployTestFrabric.js");
const { FrabricProposalType, ParticipantType, GovernorStatus, proposal, queueAndComplete } = require("../common.js");

let signers, deployer, kyc, genesis, governor;
let usdc, pair;
let bond, threadDeployer;
let frbc, frabric, nextID;

// TODO: Test supermajority is used where it should be

describe("Frabric", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [deployer, kyc, genesis, governor] = signers.splice(0, 4);

    const addrs = await deployTestFrabric(); // TODO: Check the events/behavior from upgrade
    usdc = (await ethers.getContractFactory("TestERC20")).attach(addrs.usdc).connect(deployer);
    pair = new ethers.Contract(
      addrs.pair,
      require("@uniswap/v2-core/build/UniswapV2Pair.json").abi,
      governor
    );
    bond = (await ethers.getContractFactory("Bond")).attach(addrs.bond).connect(governor);
    threadDeployer = (await ethers.getContractFactory("ThreadDeployer")).attach(addrs.threadDeployer);
    frbc = (await ethers.getContractFactory("FrabricERC20")).attach(addrs.frbc).connect(genesis);
    frabric = (await ethers.getContractFactory("Frabric")).attach(addrs.frabric).connect(genesis);

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
    await expect(
      frabric.proposeParticipants(
        ParticipantType.Genesis,
        ethers.constants.HashZero,
        ethers.utils.id("Proposing genesis participants")
      )
    ).to.be.revertedWith("ProposingGenesisParticipants()");
  });

  it("should let you add KYC agencies", async () => {
    const [ kyc ] = signers.splice(0, 1);
    const pID = nextID;
    nextID++;
    await expect(
      await proposal(frabric, "Participants", pID, [ParticipantType.KYC, kyc.address.toLowerCase() + "000000000000000000000000"])
    ).to.emit(frabric, "ParticipantChange").withArgs(kyc.address, ParticipantType.KYC);

    // Verify they were successfully added
    // They will not be present on the token's whitelist
    expect(await frabric.participant(kyc.address)).to.equal(ParticipantType.KYC);
    assert(await frabric.canPropose(kyc.address));
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
      // We could keep using nextID and increment when we're done with it, yet
      // then, if this test fails, it will never be incremented and bork the
      // rest of these test cases
      const pID = nextID;
      nextID++;
      await proposal(frabric, "Participants", pID, [pType, merkle.getHexRoot()])

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
      await expect(
        await frabric.approve(
          pID,
          signArgs[2].participant,
          signArgs[2].kycHash,
          merkle.getHexProof(signArgs[2].participant + "000000000000000000000000"),
          signature
        )
      ).to.emit(frabric, "ParticipantChange").withArgs(signArgs[2].participant, pType);

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
    await proposal(frabric, "Participants", pID, [ParticipantType.Governor, governor.address.toLowerCase() + "000000000000000000000000"]);
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
    await expect(
      await frabric.approve(
        pID,
        signArgs[2].participant,
        signArgs[2].kycHash,
        [],
        signature
      )
    ).to.emit(frabric, "ParticipantChange").withArgs(signArgs[2].participant, ParticipantType.Governor);

    // Verify they were successfully added
    expect(await frbc.info(governor.address)).to.equal(signArgs[2].kycHash);
    expect(await frabric.participant(governor.address)).to.equal(ParticipantType.Governor);
    expect(await frabric.governor(governor.address)).to.equal(GovernorStatus.Active);
    assert(await frabric.canPropose(governor.address));
  });

  // Not routed through the Frabric at all other than the GovernorStatus, which
  // Bond uses a TestFrabric with to test. Just needs to be done and having this
  // isolated code block for it is beneficial
  it("should let governors add bond", async () => {
    await frbc.transfer(pair.address, 10000);
    await usdc.transfer(pair.address, 10000);
    await pair.mint(governor.address);

    await pair.approve(bond.address, 9000);
    await bond.bond(9000);
  });

  it("should let you remove bond", async () => {
    const pID = nextID;
    nextID++;
    await expect(
      await proposal(frabric, "RemoveBond", pID, [governor.address, false, 3333])
    ).to.emit(bond, "Unbond").withArgs(governor.address, 3333);
    expect(await pair.balanceOf(governor.address)).to.equal(3333);
  });

  it("should let you slash bond", async () => {
    const pID = nextID;
    nextID++;
    await expect(
      await proposal(frabric, "RemoveBond", pID, [governor.address, true, 5667])
    ).to.emit(bond, "Slash").withArgs(governor.address, 5667);
    expect(await pair.balanceOf(frabric.address)).to.equal(5667);
  });

  it("should let you create a Thread", async () => {
    const descriptor = "0x" + (new Buffer.from("ipfs").toString("hex")).repeat(8);
    const data = (new ethers.utils.AbiCoder()).encode(
      ["address", "uint256"],
      [usdc.address, 1000]
    );

    const pID = nextID;
    nextID++;

    const tx = await proposal(
      frabric,
      "Thread",
      pID,
      [0, "Test Thread", "TTHR", descriptor, governor.address, data],
      [0, 4, 1, 2, 3, 5]
    );

    // Grab unknown event arguments due to Waffle's lack of partial event matching
    const thread = (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.thread;
    const erc20 = (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.erc20;
    const crowdfund = (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()))[0].args.crowdfund;

    await expect(tx).to.emit(threadDeployer, "Thread").withArgs(thread, 0, governor.address, erc20, descriptor);
    await expect(tx).to.emit(threadDeployer, "CrowdfundedThread").withArgs(thread, usdc.address, crowdfund, 1000);
  });

  it("should let you create a proposal on a Thread", async () => {
    // TODO
  });

  // Participant removals are tested by the FrabricDAO test, yet the Frabric
  // defines a hook
  it("should correctly handle participant removals", async () => {
    // Remove the governor as they have additional code in the hook, making them
    // the single complete case
    const pID = nextID;
    nextID++;
    await expect(
      await proposal(frabric, "ParticipantRemoval", pID, [governor.address, 0, []])
    ).to.emit(frabric, "ParticipantChange").withArgs(governor.address, ParticipantType.Removed);
    expect(await frbc.info(governor.address)).to.equal(ethers.constants.HashZero);
    expect(await frabric.participant(governor.address)).to.equal(ParticipantType.Removed);
    expect(await frabric.governor(governor.address)).to.equal(GovernorStatus.Removed);
    assert(!(await frabric.canPropose(governor.address)));
  });

  // Used to practically demonstrate the delay is sufficient for all actions in a e2e test
  it("should let you sell the tokens from a leaving Thread", async () => {
    // TODO
  });
});
