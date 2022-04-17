const hre = require("hardhat");
const { ethers } = hre;

const deployInitialFrabric = require("../../scripts/deployInitialFrabric.js");
const deployFrabric = require("../../scripts/deployFrabric.js");

const deployUniswap = require("../scripts/deployUniswap.js");
const { queueAndComplete } = require("../common.js");

module.exports = async () => {
  // Redundant with `npx hardhat test`, yet supports running as
  // `node test/scripts/deployTestFrabric.js` to ensure compilation and
  // initialization still works as expected
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signers = await ethers.getSigners();

  const usdc = (await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD")).address;
  const uniswap = await deployUniswap();

  let genesis = {};
  genesis[signers[2].address] = {
    info: "Hardhat Account 2",
    amount: "100000000000000000000"
  };

  let contracts = await deployInitialFrabric(usdc, uniswap.router.address, genesis);
  contracts.usdc = usdc;

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

  frabric = (await ethers.getContractFactory("InitialFrabric")).attach(frabric).connect(signers[2]);
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
  await queueAndComplete(frabric, 1);

  proxy = (await ethers.getContractFactory("SingleBeacon")).attach(proxy);
  await proxy.triggerUpgrade(frabric.address, 2);

  // Actually create the pair
  await (new ethers.Contract(
    uniswap.factory.address,
    require("@uniswap/v2-core/build/UniswapV2Factory.json").abi,
    signers[0]
  )).createPair(frbc, usdc);

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
