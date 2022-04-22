const { ethers, waffle, network } = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");
const { OrderType, proposal } = require("../common.js");

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
    await frbc.mint(fDAO.address, ethers.utils.parseUnits("1"));
    await frbc.transferOwnership(fDAO.address);
  });

  it("should have initialized correctly", async () => {
    expect(await fDAO.commonProposalBit()).to.equal(256);
    expect(await fDAO.maxRemovalFee()).to.equal(5);
  });

  it("should have paper proposals", async () => {
    // Since Paper proposals are literally a NOP dependent on the info string, this is sufficient
    await proposal(fDAO, "Paper", []);
  });

  it("should allow upgrading", async () => {
    // TODO, implicitly tested by deployTestFrabric
  });

  it("should allow transferring tokens", async () => {
    await usd.transfer(fDAO.address, 111);

    const other = signers.splice(0, 1)[0].address;
    const tx = (await proposal(fDAO, "TokenAction", [usd.address, other, false, 0, 111])).tx;
    await expect(tx).to.emit(usd, "Transfer").withArgs(fDAO.address, other, 111);

    expect(await usd.balanceOf(other)).to.equal(111);
  });

  it("should allow selling tokens on their DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, fDAO.address, false, 2, ethers.utils.parseUnits("1")])).tx;
    await expect(tx).to.emit(frbc, "NewOrder").withArgs(OrderType.Sell, 2);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(fDAO.address, 2, 1);
    expect(await frbc.locked(fDAO.address)).to.equal(ethers.utils.parseUnits("1"));
  });

  it("should allow cancelling orders on a DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, fDAO.address, false, 2, 0])).tx;
    await expect(tx).to.emit(frbc, "CancelledOrder").withArgs(fDAO.address, 2, 1);
    expect(await frbc.locked(fDAO.address)).to.equal(ethers.utils.parseUnits("0"));
  });

  it("should allow selling tokens at auction", async () => {
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, auction.address, false, 0, ethers.utils.parseUnits("1")])).tx;
    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await expect(tx).to.emit(frbc, "Approval").withArgs(fDAO.address, auction.address, ethers.utils.parseUnits("1"));
    await expect(tx).to.emit(frbc, "Transfer").withArgs(fDAO.address, auction.address, ethers.utils.parseUnits("1"));
    await expect(tx).to.emit(auction, "NewAuction").withArgs(0, fDAO.address, frbc.address, usd.address, ethers.utils.parseUnits("1"), time, 7 * 24 * 60 * 60);
    expect(await frbc.balanceOf(fDAO.address)).to.equal(0);
    expect(await frbc.balanceOf(auction.address)).to.equal(ethers.utils.parseUnits("1"));
  });

  // The following tests pass if you uncomment the NotMintable line of FrabricDAO
  // which forces all mint proposals to fail
  it("should allow minting tokens", async () => {
    const other = signers.splice(0, 1)[0].address;
    await fDAO.whitelist(other);

    const supply = await frbc.totalSupply();
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, other, true, 0, 222])).tx;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, other, 222);
    expect(await frbc.totalSupply()).to.equal(supply.add(222));
    expect(await frbc.balanceOf(other)).to.equal(222);
  });

  it("should allow minting and selling on the DEX", async () => {
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, fDAO.address, true, 2, ethers.utils.parseUnits("2")])).tx;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, fDAO.address, ethers.utils.parseUnits("2"));
    await expect(tx).to.emit(frbc, "NewOrder").withArgs(OrderType.Sell, 2);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(fDAO.address, 2, 2);
    expect(await frbc.locked(fDAO.address)).to.equal(ethers.utils.parseUnits("2"));
  });

  it("should allow minting and selling at Auction", async () => {
    const tx = (await proposal(fDAO, "TokenAction", [frbc.address, auction.address, true, 0, ethers.utils.parseUnits("2")])).tx;
    const time = (await waffle.provider.getBlock("latest")).timestamp;
    await expect(tx).to.emit(frbc, "Transfer").withArgs(ethers.constants.AddressZero, fDAO.address, ethers.utils.parseUnits("2"));
    await expect(tx).to.emit(frbc, "Approval").withArgs(fDAO.address, auction.address, ethers.utils.parseUnits("2"));
    await expect(tx).to.emit(frbc, "Transfer").withArgs(fDAO.address, auction.address, ethers.utils.parseUnits("2"));
    await expect(tx).to.emit(auction, "NewAuction").withArgs(1, fDAO.address, frbc.address, usd.address, ethers.utils.parseUnits("2"), time, 7 * 24 * 60 * 60);
    expect(await frbc.balanceOf(auction.address)).to.equal(ethers.utils.parseUnits("3"));
  });

  it("should allow removing participants", async () => {
    // TODO
  });

  /*
    _canProposeUpgrade
    _canProposeRemoval
    proposeParticipantRemoval(
      address participant,
      uint8 removalFee,
      bytes[] calldata signatures,
      bytes32 info
    )
    _participantRemoval(address participant)
  */

  // Doesn't test _completeSpecificProposal is called as it's implicitly
  // tested to be successfully called by the Frabric/Thread tests
});
