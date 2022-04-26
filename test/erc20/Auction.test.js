const { ethers, waffle } = require("hardhat");
const { expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { increaseTime } = require("../common.js");

let signers, deployer, seller, bidder, winner;
let whitelist, usd, auction, frbc;

let defaultArgs;

const WEEK = 7 * 24 * 60 * 60;

// Helper function to generate custom arguments without specifying all 7
function override(args, includeBatches) {
  args = { ...defaultArgs, ...args };
  let res = [args.seller, args.token, args.traded, args.amount];
  if (includeBatches) {
    res.push(args.batches);
  }
  return [...res, args.start, args.length];
}

async function list(id, args) {
  // Ensure args is splattable
  if (!args) {
    args = {};
  }

  // Approve the Auction contract to spend these tokens
  args.amount = args.amount ? args.amount : defaultArgs.amount;
  await frbc.approve(auction.address, args.amount);
  const before = await frbc.balanceOf(auction.address);

  // Create the listing
  const tx = await auction.list(...override(args, true));

  // verify the balance was transferred
  await expect(tx).to.emit(frbc, "Transfer").withArgs(seller.address, auction.address, args.amount);
  expect(await frbc.balanceOf(auction.address)).to.equal(before.add(args.amount));

  // If auction normalized the start time, do the same here
  const time = (await waffle.provider.getBlock("latest")).timestamp;
  if (!args.start) {
    args.start = time;
  }
  args.length = args.length ? args.length : defaultArgs.length;

  // Calculate the per batch amount
  args.batches = args.batches ? args.batches : defaultArgs.batches;
  let last = args.amount % args.batches;
  args.amount = Math.floor(args.amount / args.batches);

  // Check each created auction
  for (let i = 0; i < args.batches; i++) {
    // Apply the rounding error to the last batch
    if (i === (args.batches - 1)) {
      args.amount += last;
    }

    await expect(tx).to.emit(auction, "Listing").withArgs(id + i, ...override(args, false));
    expect(await auction.active(id + i)).to.equal(args.start <= time);
    expect(await auction.highestBidder(id + i)).to.equal(ethers.constants.AddressZero);
    expect(await auction.highestBid(id + i)).to.equal(0);
    expect(await auction.end(id + i)).to.equal(args.start + args.length);

    // Increment the start time for the next auction
    args.start += args.length;
  }

  return tx;
}

async function bid(signer, id, amount) {
  // Track the current bidder if one exists
  const oldBidder = await auction.highestBidder(id);
  let oldBalance, oldBid;
  if (oldBidder !== ethers.constants.AddressZero) {
    oldBalance = await auction.balances(usd.address, oldBidder);
    oldBid = await auction.highestBid(id);
  }

  // Place the bid
  await whitelist.whitelist(signer.address);
  await usd.connect(signer).approve(auction.address, amount);
  const before = await usd.balanceOf(auction.address);
  const tx = await auction.connect(signer).bid(id, amount);

  // Verify the state change
  await expect(tx).to.emit(usd, "Transfer").withArgs(signer.address, auction.address, amount);
  await expect(tx).to.emit(auction, "Bid").withArgs(id, signer.address, amount);
  expect(await usd.balanceOf(auction.address)).to.equal(before.add(amount));
  expect(await auction.highestBidder(id)).to.be.equal(signer.address);
  expect(await auction.highestBid(id)).to.be.equal(amount);

  // Make sure the old bidder had their funds returned
  if (oldBidder !== ethers.constants.AddressZero) {
    expect(await auction.balances(usd.address, oldBidder)).to.equal(oldBalance.add(oldBid));
  }
}

async function complete(id) {
  const tx = await auction.complete(id);
  expect(await auction.active(id)).to.equal(false);
  await expect(tx).to.emit(auction, "AuctionComplete").withArgs(id);
  return tx;
}

describe("Auction", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    [ deployer, seller, bidder, winner ] = signers.splice(0, 4);

    whitelist = await (await ethers.getContractFactory("TestFrabric")).deploy();
    usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");

    let beacon = await FrabricERC20.deployBeacon();
    ({ auction, erc20: frbc } = await FrabricERC20.deploy(
      beacon,
      ["Test FrabricERC20", "FRBC", 0, whitelist.address, usd.address]
    ));
    await frbc.remove(deployer.address, 0);

    await whitelist.whitelist(auction.address);

    await whitelist.whitelist(seller.address);
    await frbc.mint(seller.address, 1000);

    // Shift from deployer to seller
    await usd.transfer(seller.address, await usd.balanceOf(deployer.address));
    usd = usd.connect(seller);
    auction = auction.connect(seller);
    frbc = frbc.connect(seller);

    defaultArgs = {
      seller: seller.address,
      token: frbc.address,
      traded: usd.address,
      amount: 100,
      batches: 1,
      start: 0,
      length: WEEK
    };
  });

  it("should let you create auctions", async () => {
    await list(0);
  });

  it("should let you create auctions in the future", async () => {
    await list(1, { start: (await waffle.provider.getBlock("latest")).timestamp + WEEK, amount: 202 });
  });

  it("should let you create auctions in batches", async () => {
    await list(2, { amount: 303, batches: 4 });
  });

  it("should let the token create auctions for you", async () => {
    // TODO, though implicitly tested elsewhere
  });

  it("shouldn't let anyone create auctions for you", async () => {
    await expect(
      list(6, { seller: bidder.address })
    ).to.be.revertedWith(`Unauthorized("${seller.address}", "${bidder.address}")`);
  });

  it("shouldn't let you bid if you're not whitelisted", async () => {
    await usd.transfer(bidder.address, 1);
    await usd.connect(bidder).approve(auction.address, 1);
    await expect(
      auction.connect(bidder).bid(0, 1)
    ).to.be.revertedWith(`NotWhitelisted("${bidder.address}")`);
  });

  it("should let you bid", async () => {
    await bid(bidder, 0, 1);
  });

  it("should let you outbid", async () => {
    await usd.transfer(winner.address, 2);
    await bid(winner, 0, 2);
  });

  // Prepares the next set of tests
  it("should let time pass", async () => {
    await increaseTime((2 * WEEK) + 1);
  });

  it("should let you complete auctions", async () => {
    await expect(await complete(0)).to.emit(auction, "AuctionComplete").withArgs(0);
    expect(await auction.balances(frbc.address, winner.address)).to.equal(100);
    expect(await auction.balances(usd.address, seller.address)).to.equal(2);
  });

  it("should complete auctions where no one bids", async () => {
    await complete(1);
    expect(await auction.balances(frbc.address, seller.address)).to.equal(202);
  });

  it("should complete auctions where no one bids and the seller is no longer whitelisted", async () => {
    await whitelist.remove(seller.address);
    await expect(
      await complete(2)
    ).to.emit(frbc, "Transfer").withArgs(auction.address, ethers.constants.AddressZero, 75);
    expect(await auction.balances(frbc.address, seller.address)).to.equal(202);
  });

  // This isn't expected to happen yet is expected to work if it does
  it("should complete auctions where no one bids, not whitelisted, and burn doesn't exist", async () => {
    // TODO
  });

  it("should let you withdraw", async () => {
    await expect(
      await auction.withdraw(frbc.address, winner.address)
    ).to.emit(frbc, "Transfer").withArgs(auction.address, winner.address, 100);
    expect(await auction.balances(frbc.address, winner.address)).to.equal(0);
  });
});
