const { ethers, waffle, network } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");
const { OrderType, propose, queueAndComplete, proposal } = require("../common.js");

const WEEK = 7 * 24 * 60 * 60;
const ONE = ethers.utils.parseUnits("1");
const TWO = ethers.utils.parseUnits("2");

let signers, deployer, participant;
let usd, auction, frbc, fDAO;

// TODO: Test supermajority is used where it should be

describe("FrabricDAO", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [ deployer, participant ] = signers.splice(0, 2);

    usd = await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD");
    ({ frbc, auction } = await FrabricERC20.deployFRBC(usd.address));
    await frbc.setWhitelisted(auction.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.setWhitelisted(participant.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.mint(participant.address, ethers.utils.parseUnits("5"));
    fDAO = (await (await ethers.getContractFactory("TestFrabricDAO")).deploy(frbc.address)).connect(participant);
    await frbc.setWhitelisted(fDAO.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.mint(fDAO.address, ONE);
    await frbc.transferOwnership(fDAO.address);
    frbc = frbc.connect(participant);
  });

  it("should have initialized correctly", async () => {
    expect(await fDAO.commonProposalBit()).to.equal(256);
    expect(await fDAO.maxRemovalFee()).to.equal(5);
  });

  it("should have paper proposals", async () => {
    // Since Paper proposals are literally a NOP dependent on the info string, this is sufficient
    await proposal(fDAO, "Paper", false, []);
  });

  it("should allow upgrading", async () => {
    // TODO, implicitly tested by deployTestFrabric
  });

  it("should allow transferring tokens", async () => {
    await usd.transfer(fDAO.address, 111);

    const other = signers.splice(0, 1)[0].address;
    const tx = (await proposal(fDAO, "TokenAction", false, [usd.address, other, false, 0, 111])).tx;
    await expect(tx).to.emit(usd, "Transfer").withArgs(fDAO.address, other, 111);

    expect(await usd.balanceOf(other)).to.equal(111);
  });

  it("should allow selling tokens on their DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", false, [frbc.address, fDAO.address, false, 2, ONE])).tx;
    await expect(tx).to.emit(frbc, "Order").withArgs(OrderType.Sell, 2);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(fDAO.address, 2, 1);
    expect(await frbc.locked(fDAO.address)).to.equal(ONE);
  });

  it("should allow cancelling orders on a DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", false, [frbc.address, fDAO.address, false, 2, 0])).tx;
    await expect(tx).to.emit(frbc, "OrderCancellation").withArgs(fDAO.address, 2, 1);
    expect(await frbc.locked(fDAO.address)).to.equal(ethers.utils.parseUnits("0"));
  });

  it("should allow selling tokens at auction", async () => {
    const tx = (await proposal(fDAO, "TokenAction", false, [frbc.address, auction.address, false, 0, ONE])).tx;
    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await expect(tx).to.emit(frbc, "Approval").withArgs(fDAO.address, auction.address, ONE);
    await expect(tx).to.emit(frbc, "Transfer").withArgs(fDAO.address, auction.address, ONE);
    await expect(tx).to.emit(auction, "Auctions").withArgs(0, fDAO.address, frbc.address, usd.address, ONE, 1, time, WEEK);
    expect(await frbc.balanceOf(fDAO.address)).to.equal(0);
    expect(await frbc.balanceOf(auction.address)).to.equal(ONE);
  });

  // The following tests pass if the NotMintable line of FrabricDAO which forces
  // all mint proposals to fail is commented
  it("should allow minting tokens", async () => {
    const other = signers.splice(0, 1)[0].address;
    await fDAO.whitelist(other);

    const supply = await frbc.totalSupply();
    const tx = (await proposal(fDAO, "TokenAction", true, [frbc.address, other, true, 0, 222])).tx;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, other, 222);
    expect(await frbc.totalSupply()).to.equal(supply.add(222));
    expect(await frbc.balanceOf(other)).to.equal(222);
  });

  it("should allow minting and selling on the DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", true, [frbc.address, fDAO.address, true, 2, TWO])).tx;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, fDAO.address, TWO);
    await expect(tx).to.emit(frbc, "Order").withArgs(OrderType.Sell, 2);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(fDAO.address, 2, 2);
    expect(await frbc.locked(fDAO.address)).to.equal(TWO);
  });

  it("should allow minting and selling at Auction", async () => {
    const tx = (await proposal(fDAO, "TokenAction", true, [frbc.address, auction.address, true, 0, TWO])).tx;
    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, fDAO.address, TWO);
    await expect(tx).to.emit(frbc, "Approval").withArgs(fDAO.address, auction.address, TWO);
    await expect(tx).to.emit(frbc, "Transfer").withArgs(fDAO.address, auction.address, TWO);
    await expect(tx).to.emit(auction, "Auctions").withArgs(1, fDAO.address, frbc.address, usd.address, TWO, 1, time, WEEK);
    expect(await frbc.balanceOf(auction.address)).to.equal(ethers.utils.parseUnits("3"));
  });

  it("should allow removing participants", async () => {
    for (let i = 0; i < 3; i++) {
      const other = signers.splice(0, 1)[0];
      await fDAO.whitelist(other.address);
      await frbc.transfer(other.address, 100);

      let removalFee = 0;
      let signatures = [];
      // Remove 5% for rounds 1 and 2
      if (i !== 0) {
        removalFee = 5;
      }

      // Freeze for the last round
      if (i === 2) {
        const signArgs = [
          {
            name: "Test Frabric DAO",
            version: "1",
            chainId: 31337,
            verifyingContract: fDAO.address
          },
          {
            Removal: [
              { name: "participant", type: "address" }
            ]
          },
          {
            participant: other.address
          }
        ];
        if (participant.signTypedData) {
          signaturess = [await participant.signTypedData(...signArgs)];
        } else {
          signatures = [await participant._signTypedData(...signArgs)];
        }
      }

      const { id, tx: freeze } = await propose(fDAO, "ParticipantRemoval", false, [other.address, removalFee, signatures]);
      if (i === 2) {
        let frozenUntil = (await waffle.provider.getBlock("latest")).timestamp + WEEK + (3 * 24 * 60 * 60);
        await expect(freeze).to.emit(frbc, "Freeze").withArgs(other.address, frozenUntil);
        expect(await frbc.frozenUntil(other.address)).to.equal(frozenUntil);
        await expect(
          frbc.connect(other).transfer(participant.address, 1)
        ).to.be.revertedWith(`Frozen("${other.address}")`);
      }

      const tx = await queueAndComplete(fDAO, id);
      await expect(tx).to.emit(frbc, "Whitelisted").withArgs(other.address, false);
      if (removalFee !== 0) {
        await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, fDAO.address, removalFee);
      }
      await expect(tx).to.emit(frbc, "Approval").withArgs(other.address, auction.address, 100 - removalFee);
      await expect(tx).to.emit(frbc, "Transfer").withArgs(other.address, auction.address, 100 - removalFee);

      await expect(tx).to.emit(auction, "Auctions").withArgs(
        2 + (i * 4),
        other.address,
        frbc.address,
        usd.address,
        100 - removalFee,
        4,
        (await waffle.provider.getBlock("latest")).timestamp,
        WEEK
      );
      await expect(tx).to.emit(frbc, "Removal").withArgs(other.address, 100);
      await expect(tx).to.emit(fDAO, "RemovalHook").withArgs(other.address);

      expect(await frbc.whitelisted(other.address)).to.equal(false);
      expect(await frbc.balanceOf(other.address)).to.equal(0);
      expect(await frbc.locked(other.address)).to.equal(0);
    }
  });

  // TODO: _canProposeUpgrade and _canProposeRemoval hooks. Thread does tests both

  // Doesn't test _completeSpecificProposal is called as it's implicitly
  // tested to be successfully called by the Frabric/Thread tests
});
