const hre = require("hardhat");
const { ethers, upgrades, waffle } = hre;

const u2SDK = require("@uniswap/v2-sdk");
const uSDK = require("@uniswap/sdk-core");

const deployBeacon = require("./deployBeacon.js");
const deployBeaconProxy = require("./deployBeaconProxy.js");
const FrabricERC20 = require("./deployFrabricERC20.js");
const deployDEXRouter = require("./deployDEXRouter.js");

module.exports = async (usd, uniswap, genesis, votingPeriod, queuePeriod, lapsePeriod) => {

  if (!queuePeriod) {
    queuePeriod = 60 * 60 * 24 * 2;
  }
  if (!lapsePeriod) {
    lapsePeriod = 60 * 60 * 24 * 2;
  }
  if (!votingPeriod) {
    votingPeriod = 60 * 60 * 24 * 7;
  }
  // Run compile if it hasn't been run already
  // Prevents a print statement of "Nothing to compile" from repeatedly appearing
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signer = (await ethers.getSigners())[0];
  console.log("starting deploy")
  const { auctionBeacon, auction, beacon: erc20Beacon, frbc } = await FrabricERC20.deployFRBC(usd);
  console.log("deployed FRBC")
  await (await frbc.whitelist(auction.address)).wait();

  // Deploy the Uniswap pair to get the bond token
  uniswap = new ethers.Contract(
      uniswap,
      require("@uniswap/v2-periphery/build/UniswapV2Router02.json").abi,
      signer
  );
  console.log("deployed uniswap")

  const pair = u2SDK.computePairAddress({
    factoryAddress: await uniswap.factory(),
    tokenA: new uSDK.Token(1, usd, 18),
    tokenB: new uSDK.Token(1, frbc.address, 18)
  });
  console.log("deployed pair")
  // Whitelisting the pair to create the LP token does break the whitelist to some degree
  // We're immediately creating a wrapped derivative token with no transfer limitations
  // That said, it's a derivative subject to reduced profit potential and unusable as FRBC
  // Considering the critical role Uniswap plays in the Ethereum ecosystem, we accordingly accept this effect
  await (await frbc.whitelist(pair)).wait();
  console.log("whitelisted pair")
  // Process the genesis
  let genesisList = [];
  for (const person in genesis) {
    await (await frbc.whitelist(person, { gasLimit: 300000 })).wait();
    await (await frbc.setKYC(person, ethers.utils.id(genesis[person].info), 0, { gasLimit: 300000 })).wait();
    await (await frbc.mint(person, genesis[person].amount, { gasLimit: 300000 })).wait();

    genesisList.push(person);
  }
  console.log("updated genesis list")


  // Remove self from the FRBC whitelist
  // While we have no powers over the Frabric, we can hold tokens
  // This is a mismatched state when we shouldn't have any powers except as needed to deploy
  await (await frbc.remove(signer.address, 0)).wait();
  console.log("removed self from whitelist")
  const InitialFrabric = await ethers.getContractFactory("InitialFrabric");
  const beacon = await deployBeacon("single", InitialFrabric);

  const frabric = await deployBeaconProxy(beacon.address, InitialFrabric,
      [frbc.address,
        genesisList,
          votingPeriod,
          queuePeriod,
          lapsePeriod
      ]);
  console.log("deployed InitialFrabric beaconproxy")
  await (await frbc.whitelist(frabric.address)).wait();

  // Transfer ownership of everything to the Frabric
  // The Auction isn't owned as it doesn't need to be
  // While it does need to be upgraded, it tracks the (sole) release channel of its SingleBeacon
  // That's what needs to be owned
  await (await auctionBeacon.transferOwnership(frabric.address)).wait();
  // FrabricERC20 beacon and FRBC
  await (await erc20Beacon.transferOwnership(frabric.address)).wait();
  await (await frbc.transferOwnership(frabric.address)).wait();
  // Frabric proxy
  await beacon.transferOwnership(frabric.address);
  console.log("ownership transferred to beaconProxy")
  // Deploy the DEX router
  // Technically a periphery contract yet this script treats InitialFrabric as
  // the initial entire ecosystem, not just itself
  const router = await deployDEXRouter();
  console.log("deployed DEX")
  return {
    auction,
    erc20Beacon,
    frbc,
    pair,
    beacon,
    frabric,
    router
  };
};

if (require.main === module) {
  (async () => {
    let usd = process.env.USD;
    let uniswap = process.env.UNISWAP;
    let queuePeriod = process.env.QUEUEPERIOD;
    let lapsePeriod = process.env.LAPSEPERIOD;
    let votingPeriod = process.env.VOTINGPERIOD;
    let genesis;

    if ((!usd) || (!uniswap)) {
      console.error("Only some environment variables were provide. Provide USD and the Uniswap v2 Router.");
      process.exit(1);
    }
    genesis = require("../genesis.json");

    const contracts = await module.exports(usd, uniswap, genesis, votingPeriod, lapsePeriod, queuePeriod);
    console.log("Auction:         " + contracts.auction.address);
    console.log("ERC20 Beacon:    " + contracts.erc20Beacon.address);
    console.log("FRBC:            " + contracts.frbc.address);
    console.log("FRBC-USD Pair:   " + contracts.pair);
    console.log("Initial Frabric: " + contracts.frabric.address);
    console.log("DEX Router:      " + contracts.router.address);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}