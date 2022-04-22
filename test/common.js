const { waffle } = require("hardhat");
const { expect } = require("chai");

module.exports = {
  OrderType: {
    Null: 0,
    Buy: 1,
    Sell: 2
  },

  ProposalState: {
    Null: 0,
    Active: 1,
    Queued: 2,
    Executed: 3,
    Cancelled: 4
  },

  CommonProposalType: {
    Paper: 256,
    Upgrade: 257,
    TokenAction: 258,
    ParticipantRemoval: 259
  },

  FrabricProposalType: {
    Participants: 0,
    RemoveBond: 1,
    Thread: 2,
    ThreadProposal: 3
  },

  ParticipantType: {
    Null: 0,
    Removed: 1,
    Genesis: 2,
    KYC: 3,
    Governor: 4,
    Individual: 5,
    Corporation: 6
  },

  GovernorStatus: {
    Null: 0,
    Unverified: 1,
    Active: 2,
    Removed: 3
  },

  ThreadProposalType: {
    DescriptorChange: 0,
    FrabricChange: 1,
    GovernorChange: 2,
    EcosystemLeaveWithUpgrades: 3,
    Dissolution: 4
  },

  snapshot: () => waffle.provider.send("evm_snapshot", []),
  revert: (id) => waffle.provider.send("evm_revert", [id]),
  increaseTime: (time) => waffle.provider.send("evm_increaseTime", [time]),

  propose: async (dao, proposal, args, order) => {
    let ProposalType;
    if (module.exports.CommonProposalType.hasOwnProperty(proposal)) {
      ProposalType = module.exports.CommonProposalType;
    } else if ((await dao.contractName()) == ethers.utils.id("Frabric")) {
      ProposalType = module.exports.FrabricProposalType;
    } else {
      ProposalType = module.exports.ThreadProposalType;
    }

    const id = await dao.nextProposalID();

    const info = ethers.utils.id(proposal);
    // Don't chain due to https://github.com/TrueFiEng/Waffle/issues/595 and
    // https://github.com/TrueFiEng/Waffle/issues/647
    // withArgs is unstable to the point these tests might be finely reviewed by
    // a human and it's honestly unsafe to call them sufficient until either
    // waffle corrects it OR withArgs is completely replaced
    // TODO
    const tx = await dao["propose" + proposal](...args, info);
    await expect(tx).to.emit(dao, "NewProposal").withArgs(
      id,
      ProposalType[proposal],
      dao.signer.address,
      info
    );
    await expect(tx).to.emit(dao, "ProposalStateChanged").withArgs(id, module.exports.ProposalState.Active);

    if ((typeof(args[args.length - 1]) === "object") && (!args[args.length - 1].hasOwnProperty("_isBigNumber"))) {
      args.pop();
    }

    let ordered = args;
    if (order) {
      ordered = [];
      for (let i of order) {
        ordered.push(args[i]);
      }
    }
    if (proposal !== "Paper") {
      await expect(await tx).to.emit(dao, proposal + "Proposed").withArgs(id, ...ordered);
    }

    return { id, tx };
  },

  queueAndComplete: async (dao, id) => {
    // Advance the clock by the voting period (+ 1 second)
    module.exports.increaseTime(parseInt(await dao.votingPeriod()) + 1);

    // Queue the proposal
    await expect(await dao.queueProposal(id)).to.emit(dao, "ProposalStateChanged").withArgs(id, module.exports.ProposalState.Queued);

    // Advance the clock 48 hours
    module.exports.increaseTime(2 * 24 * 60 * 60 + 1);

    // Complete it
    const tx = await dao.completeProposal(id);
    await expect(tx).to.emit(dao, "ProposalStateChanged").withArgs(id, module.exports.ProposalState.Executed);
    return tx;
  },

  proposal: async (dao, proposal, args, order) => {
    const { id } = await module.exports.propose(dao, proposal, args, order);
    return { id, tx: await module.exports.queueAndComplete(dao, id) };
  }
}
