const { ethers, waffle, network } = require("hardhat");
const { assert, expect } = require("chai");

const deployTestFrabric = require("../scripts/deployTestFrabric.js");
const { FrabricProposalType, ParticipantType, GovernorStatus, proposal, queueAndComplete } = require("../common.js");

let signGlobal = [
  {
    name: "Frabric Protocol",
    version: "1",
    chainId: 31337
  },
  {
    Vouch: [
      { type: "address", name: "participant" }
    ],
    KYCVerification: [
      { type: "uint8",   name: "participantType" },
      { type: "address", name: "participant" },
      { type: "bytes32", name: "kyc" },
      { type: "uint256", name: "nonce" }
    ]
  }
];

function sign(signer, data) {
  let signArgs = JSON.parse(JSON.stringify(signGlobal));
  if (Object.keys(data).length === 1) {
    signArgs[1] = { Vouch: signArgs[1].Vouch };
  } else {
    signArgs[1] = { KYCVerification: signArgs[1].KYCVerification };
  }

  // Shim for the fact ethers.js will change this functions names in the future
  if (signer.signTypedData) {
    return signer.signTypedData(...signArgs, data);
  } else {
    return signer._signTypedData(...signArgs, data);
  }
}

let signers, deployer, kyc, genesis, governor, voucher;
let usd, pair;
let bond, threadDeployer;
let frbc, frabric;

describe("Frabric", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [deployer, kyc, genesis, governor, voucher] = signers.splice(0, 5);

    ({
      usd, pair,
      bond, threadDeployer,
      frbc, frabric
    } = await deployTestFrabric()); // TODO: Check the events/behavior from upgrade

    // Connect as beneficial for testing
    pair = pair.connect(governor);
    bond = bond.connect(governor);
    frbc = frbc.connect(genesis);
    frabric = frabric.connect(genesis);

    signGlobal[0].verifyingContract = frabric.address;
  });

  it("should have the expected bond/threadDeployer", async () => {
    expect(await frabric.bond()).to.equal(bond.address);
    expect(await frabric.threadDeployer()).to.equal(threadDeployer.address);
  });

  it("shouldn't let anyone propose", async () => {
    assert(!(await frabric.canPropose(signers[1].address)));
  });

  it("shouldn't let you propose Null/Removed/Genesis participants", async () => {
    for (let pType of [ParticipantType.Null, ParticipantType.Removed, ParticipantType.Genesis]) {
      await expect(
        frabric.proposeParticipant(
          pType,
          ethers.constants.AddressZero,
          ethers.utils.id("Proposing an invalid participant")
        )
      ).to.be.revertedWith(`InvalidParticipantType(${pType})`);
    }
  });

  it("should let you add KYC agencies", async () => {
    const [ kyc ] = signers.splice(0, 1);
    await expect(
      (await proposal(frabric, "Participant", false, [ParticipantType.KYC, kyc.address], 1)).tx
    ).to.emit(frabric, "ParticipantChange").withArgs(ParticipantType.KYC, kyc.address);

    // Verify they were successfully added
    // They will not be present on the token's whitelist
    expect(await frabric.participant(kyc.address)).to.equal(ParticipantType.KYC);
    assert(await frabric.canPropose(kyc.address));
  });

  it("should let you add participants", async () => {
    for (let pType of [ParticipantType.Individual, ParticipantType.Corporation]) {
      let participant = signers.splice(0, 1)[0];

      // Vouch for the participant
      const tx = await frabric.vouch(
        participant.address,
        await sign(
          genesis,
          {
            participant: participant.address
          }
        )
      );
      await expect(tx).to.emit(frbc, "Whitelisted").withArgs(participant.address, true);
      await expect(tx).to.emit(frabric, "Vouch").withArgs(genesis.address, participant.address);

      // Approve the participant
      const kycHash = ethers.utils.id(participant.address);
      await expect(
        await frabric.approve(
          pType,
          participant.address,
          kycHash,
          await sign(
            kyc,
            {
              participantType: pType,
              participant: participant.address,
              kyc: kycHash,
              nonce: 0
            }
          )
        )
      ).to.emit(frabric, "ParticipantChange").withArgs(pType, participant.address);

      // Verify they were successfully added
      expect(await frbc.kyc(participant.address)).to.equal(kycHash);
      expect(await frabric.participant(participant.address)).to.equal(pType);
      assert(await frabric.canPropose(participant.address));
    }
  });

  it("should let you add a Governor", async () => {
    const { id, tx } = await proposal(frabric, "Participant", false, [ParticipantType.Governor, governor.address], 1);
    await expect(tx).to.emit(frbc, "Whitelisted").withArgs(governor.address, true);

    // Approve the participant
    const kycHash = ethers.utils.id("Governor");
    await expect(
      await frabric.approve(
        ParticipantType.Null,
        "0x" + "0".repeat(38) + id.toHexString().substr(2),
        kycHash,
        await sign(
          kyc,
          {
            participantType: ParticipantType.Governor,
            participant: governor.address,
            kyc: kycHash,
            nonce: 0
          }
        )
      )
    ).to.emit(frabric, "ParticipantChange").withArgs(ParticipantType.Governor, governor.address);

    // Verify they were successfully added
    expect(await frbc.kyc(governor.address)).to.equal(kycHash);
    expect(await frabric.participant(governor.address)).to.equal(ParticipantType.Governor);
    expect(await frabric.governor(governor.address)).to.equal(GovernorStatus.Active);
    assert(await frabric.canPropose(governor.address));
  });

  it("should let you add a Voucher", async () => {
    const { id } = await proposal(frabric, "Participant", false, [ParticipantType.Voucher, voucher.address], 1);

    // Approve the participant
    const kycHash = ethers.utils.id("Voucher");
    await expect(
      await frabric.approve(
        ParticipantType.Null,
        "0x" + "0".repeat(38) + id.toHexString().substr(2),
        kycHash,
        await sign(
          kyc,
          {
            participantType: ParticipantType.Voucher,
            participant: voucher.address,
            kyc: kycHash,
            nonce: 0
          }
        )
      )
    ).to.emit(frabric, "ParticipantChange").withArgs(ParticipantType.Voucher, voucher.address);

    // Verify they were successfully added
    expect(await frbc.kyc(voucher.address)).to.equal(kycHash);
    expect(await frabric.participant(voucher.address)).to.equal(ParticipantType.Voucher);
    assert(await frabric.canPropose(voucher.address));
  });

  // Not routed through the Frabric at all other than the GovernorStatus, which
  // Bond uses a TestFrabric with to test. Just needs to be done and having this
  // isolated code block for it is beneficial
  it("should let governors add bond", async () => {
    await frbc.transfer(pair.address, 10000);
    await usd.transfer(pair.address, 10000);
    await pair.mint(governor.address);

    await pair.approve(bond.address, 9000);
    await bond.bond(9000);
  });

  it("should let you remove bond", async () => {
    await expect(
      (await proposal(frabric, "BondRemoval", false, [governor.address, false, 3333])).tx
    ).to.emit(bond, "Unbond").withArgs(governor.address, 3333);
    expect(await pair.balanceOf(governor.address)).to.equal(3333);
  });

  it("should let you slash bond", async () => {
    await expect(
      (await proposal(frabric, "BondRemoval", false, [governor.address, true, 5667])).tx
    ).to.emit(bond, "Slash").withArgs(governor.address, 5667);
    expect(await pair.balanceOf(frabric.address)).to.equal(5667);
  });

  it("should let you create a Thread", async () => {
    const descriptor = ethers.utils.id("ipfs");
    const data = (new ethers.utils.AbiCoder()).encode(
      ["address", "uint112"],
      [usd.address, 1000]
    );

    const { tx } = await proposal(
      frabric.connect(governor),
      "Thread",
      false,
      [0, "Test Thread", "TTHR", descriptor, data],
      1,
      frabric.signer
    );

    // Grab unknown event arguments due to Waffle's lack of partial event matching
    const thread = (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.thread;
    const erc20 = (await threadDeployer.queryFilter(threadDeployer.filters.Thread()))[0].args.erc20;
    const crowdfund = (await threadDeployer.queryFilter(threadDeployer.filters.CrowdfundedThread()))[0].args.crowdfund;

    await expect(tx).to.emit(threadDeployer, "Thread").withArgs(thread, 0, governor.address, erc20, descriptor);
    await expect(tx).to.emit(threadDeployer, "CrowdfundedThread").withArgs(thread, usd.address, crowdfund, 1000);
  });

  it("should let you create a proposal on a Thread", async () => {
    // TODO
  });

  // Participant removals are tested by the FrabricDAO test, yet the Frabric
  // defines a hook
  it("should correctly handle participant removals", async () => {
    // Remove the governor as they have additional code in the hook, making them
    // the singular complete case
    await expect(
      (await proposal(frabric, "ParticipantRemoval", false, [governor.address, 0, 0, []])).tx
    ).to.emit(frabric, "ParticipantChange").withArgs(ParticipantType.Removed, governor.address);
    expect(await frbc.whitelisted(governor.address)).to.equal(false);
    expect(await frabric.participant(governor.address)).to.equal(ParticipantType.Removed);
    expect(await frabric.governor(governor.address)).to.equal(GovernorStatus.Removed);
    assert(!(await frabric.canPropose(governor.address)));
  });

  // Used to practically demonstrate the delay is sufficient for all actions in a e2e test
  it("should let you sell the tokens from a leaving Thread", async () => {
    // TODO
  });

  // TODO test it can upgrade all release channels and ecosystem contracts it's supposed to be able to
});
