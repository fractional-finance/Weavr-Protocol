const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

const deployBeacon = require("../../scripts/deployBeacon.js");
const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");
const deployThreadBeacon = require("../../scripts/deployThreadBeacon.js");

const { GovernorStatus } = require("../common.js");

// Doesn't use ThreadDeployer in order to prevent the need to fake an entire Crowdfund
module.exports = async () => {
  const governor = (await ethers.getSigners())[1].address;

  const TestERC20 = await ethers.getContractFactory("TestERC20");
  const token = await TestERC20.deploy("Test Token", "TERC");

  const erc20Beacon = await FrabricERC20.deployBeacon();
  const { auction, erc20 } = await FrabricERC20.deploy(erc20Beacon);

  const TestFrabric = await ethers.getContractFactory("TestFrabric");
  const frabric = await TestFrabric.deploy();
  await frabric.setGovernor(governor, GovernorStatus.Active);

  const beacon = await deployThreadBeacon();
  const Thread = await ethers.getContractFactory("Thread");
  const thread = await upgrades.deployBeaconProxy(
    beacon.address,
    Thread,
    [
      "1 Main Street",
      erc20.address,
      ethers.utils.id("ipfs"),
      frabric.address,
      governor,
      [frabric.address]
    ]
  );

  expect(await thread.votingPeriod()).to.equal(7 * 24 * 60 * 60);
  expect(await thread.maxRemovalFee()).to.equal(10);

  expect(await thread.contractName()).to.equal(ethers.utils.id("Thread"));

  expect(await thread.descriptor()).to.equal(ethers.utils.id("ipfs"));
  expect(await thread.frabric()).to.equal(frabric.address);
  expect(await thread.governor()).to.equal(governor);
  assert(await thread.irremovable(frabric.address));

  let changes = await thread.queryFilter(thread.filters.FrabricChange());
  expect(changes.length).to.equal(1);
  expect(changes[0].args.oldFrabric).to.equal(ethers.constants.AddressZero);
  expect(changes[0].args.newFrabric).to.equal(frabric.address);

  changes = await thread.queryFilter(thread.filters.GovernorChange());
  expect(changes.length).to.equal(1);
  expect(changes[0].args.oldGovernor).to.equal(ethers.constants.AddressZero);
  expect(changes[0].args.newGovernor).to.equal(governor);

  await erc20.initialize(
    "1 Main Street",
    "TTHR",
    "100000000000000000000",
    frabric.address,
    token.address,
    auction.address
  );
  await erc20.transferOwnership(thread.address);

  return { token, frabric, erc20, beacon, thread };
}

if (require.main === module) {
  module.exports()
    .then(contracts => console.log("Thread: " + contracts.thread.address))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
