const hre = require("hardhat");
const { ethers } = hre;

const deployUniswap = require("./deployUniswap.js");
const deployInitialFrabric = require("./deployInitialFrabric.js");
const deployFrabric = require("./deployFrabric.js");

const { completeProposal } = require("../test/common.js");

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signers = await ethers.getSigners();

  const usdc = (await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD")).address;
  const uniswap = (await deployUniswap()).router.address;

  let genesis = {};
  genesis[signers[2].address] = {
    info: "Hardhat Account 2",
    amount: "100000000000000000000"
  };

  let contracts = await deployInitialFrabric(usdc, uniswap, genesis);
  let {
    auction,
    erc20Beacon,
    frbc,
    pair,
    proxy,
    frabric,
    router
  } = contracts;

  const upgrade = await deployFrabric(auction, erc20Beacon, usdc, pair, frabric);
  contracts.bond = upgrade.bond;
  contracts.threadDeployer = upgrade.threadDeployer;

  frabric = new ethers.Contract(
    frabric,
    require("../artifacts/contracts/frabric/InitialFrabric.sol/InitialFrabric.json").abi,
    signers[2]
  );

  await frabric.proposeUpgrade(
    proxy,
    ethers.constants.AddressZero,
    2,
    upgrade.frabricCode,
    (new ethers.utils.AbiCoder()).encode(
      ["address", "address", "address"],
      [upgrade.bond, upgrade.threadDeployer, signers[1].address]
    ),
    ethers.utils.id("Upgrade to the Frabric")
  );
  await completeProposal(frabric, 1);

  proxy = new ethers.Contract(
    proxy,
    require("../artifacts/contracts/beacon/SingleBeacon.sol/SingleBeacon.json").abi,
    signers[0]
  )
  await proxy.triggerUpgrade(frabric.address, 2);

  return contracts;
}

if (require.main === module) {
  (async () => {
    const contracts = await module.exports();
    console.log("Auction:           " + contracts.auction);
    console.log("FRBC:              " + contracts.frbc);
    console.log("Pair (Bond Token): " + contracts.pair);
    console.log("Thread Deployer:   " + contracts.threadDeployer);
    console.log("Bond:              " + contracts.bond);
    console.log("Frabric:           " + contracts.frabric);
    console.log("DEX Router:        " + contracts.router);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
