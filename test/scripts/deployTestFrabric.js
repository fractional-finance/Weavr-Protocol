const hre = require("hardhat");
const { ethers } = hre;

const deployInitialFrabric = require("../../scripts/deployInitialFrabric.js");
const deployFrabric = require("../../scripts/deployFrabric.js");

const deployUniswap = require("../scripts/deployUniswap.js");
const { proposal } = require("../common.js");

module.exports = async () => {
  // Redundant with `npx hardhat test`, yet supports running as
  // `node test/scripts/deployTestFrabric.js` to ensure compilation and
  // initialization still works as expected
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signers = await ethers.getSigners();

  const usd = await (await ethers.getContractFactory("TestERC20")).deploy("USD Test", "USD");
  const uniswap = await deployUniswap();

  let genesis = {};
  genesis[signers[2].address] = {
    info: "Hardhat Account 2",
    amount: "100000000000000000000"
  };

  let contracts = await deployInitialFrabric(usd.address, uniswap.router.address, genesis);
  contracts.usd = usd;

  let {
    auction,
    erc20Beacon,
    frbc,
    pair,
    proxy,
    frabric
  } = contracts;

  const upgrade = await deployFrabric(auction.address, erc20Beacon.address, usd.address, pair, frabric.address);
  contracts.bond = upgrade.bond;
  contracts.threadDeployer = upgrade.threadDeployer;

  await proposal(
    frabric.connect(signers[2]),
    "Upgrade",
    true,
    [
      proxy.address,
      ethers.constants.AddressZero,
      2,
      upgrade.frabricCode,
      (new ethers.utils.AbiCoder()).encode(
        ["address", "address", "address"],
        [upgrade.bond.address, upgrade.threadDeployer.address, signers[1].address]
      )
    ]
  );

  await proxy.triggerUpgrade(frabric.address, 2);
  contracts.frabric = (await ethers.getContractFactory("Frabric")).attach(contracts.frabric.address);

  // Actually create the pair
  await uniswap.factory.createPair(frbc.address, usd.address);
  contracts.pair = new ethers.Contract(
    pair,
    require("@uniswap/v2-core/build/UniswapV2Pair.json").abi,
    signers[0]
  );

  return contracts;
}

if (require.main === module) {
  (async () => {
    const contracts = await module.exports();
    console.log("Auction:           " + contracts.auction.address);
    console.log("FRBC:              " + contracts.frbc.address);
    console.log("Pair (Bond Token): " + contracts.pair.address);
    console.log("Thread Deployer:   " + contracts.threadDeployer.address);
    console.log("Bond:              " + contracts.bond.address);
    console.log("Frabric:           " + contracts.frabric.address);
    console.log("DEX Router:        " + contracts.router.address);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
