const hre = require("hardhat");
const { ethers, upgrades, waffle } = hre;

const u2SDK = require("@uniswap/v2-sdk");
const uSDK = require("@uniswap/sdk-core");

const deployBeacon = require("./deployBeacon.js");
const FrabricERC20 = require("./deployFrabricERC20.js");
const deployDEXRouter = require("./deployDEXRouter.js");

module.exports = async (usd, uniswap, genesis) => {
  // Run compile if it hasn't been run already
  // Prevents a print statement of "Nothing to compile" from repeatedly appearing
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signer = (await ethers.getSigners())[0];

  const { auctionProxy, auction, beacon: erc20Beacon, frbc } = await FrabricERC20.deployFRBC(usd);
  await frbc.whitelist(auction.address);

  // Deploy the Uniswap pair to get the bond token
  uniswap = new ethers.Contract(
      uniswap,
      require("@uniswap/v2-periphery/build/UniswapV2Router02.json").abi,
      signer
  );

  const pair = u2SDK.computePairAddress({
    factoryAddress: await uniswap.factory(),
    tokenA: new uSDK.Token(1, usd, 18),
    tokenB: new uSDK.Token(1, frbc.address, 18)
  });
  // Whitelisting the pair to create the LP token does break the whitelist to some degree
  // We're immediately creating a wrapped derivative token with no transfer limitations
  // That said, it's a derivative subject to reduced profit potential and unusable as FRBC
  // Considering the critical role Uniswap plays in the Ethereum ecosystem, we accordingly accept this effect
  await frbc.whitelist(pair);

  // Process the genesis
  let genesisList = [];
  for (const person in genesis) {
    await frbc.whitelist(person);
    await frbc.setKYC(person, ethers.utils.id(genesis[person].info), 0);

    // Delay code from Beacon used to resolve consistent timing issues that make little sense
    if ((await waffle.provider.getNetwork()).chainId != 31337) {
      let block = await waffle.provider.getBlockNumber();
      while ((block + 2) > (await waffle.provider.getBlockNumber())) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    await frbc.mint(person, genesis[person].amount, { gasLimit: 300000 });
    if ((await waffle.provider.getNetwork()).chainId != 31337) {
      let block = await waffle.provider.getBlockNumber();
      while ((block + 2) > (await waffle.provider.getBlockNumber())) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    genesisList.push(person);
  }

  // Code to add liquidity to create the LP token used as bond
  // Also verifies the whitelist is correctly set up
  // Currently disabled in favor of createPair since the whitelist has already been verified against this
  /*
  // Mint 10000 to use as initial liquidity, just to create the LP token
  await frbc.mint(signer.address, 10000);
  await frbc.approve(uniswap.address, 10000);

  usd = new ethers.Contract(
    usd,
    // Use the test Token contract as it'll supply IERC20
    (await ethers.getContractFactory("TestERC20")).interface,
    signer
  );
  await usd.approve(uniswap.address, 10000);

  await uniswap.addLiquidity(
    usd.address,
    frbc.address,
    10000, 10000, 10000, 10000,
    signer.address,
    // Pointless deadline yet validly formed
    Math.floor((Date.now() / 1000) + 30)
  );

  usd = usd.address;
  */

  // Remove self from the FRBC whitelist
  // While we have no powers over the Frabric, we can hold tokens
  // This is a mismatched state when we shouldn't have any powers except as needed to deploy
  frbc.remove(signer.address, 0);

  const InitialFrabric = await ethers.getContractFactory("InitialFrabric");
  const proxy = await deployBeacon("single", InitialFrabric);

  const frabric = await upgrades.deployBeaconProxy(proxy.address, InitialFrabric, [frbc.address, genesisList]);
  await frbc.whitelist(frabric.address);

  // Transfer ownership of everything to the Frabric
  // The Auction isn't owned as it doesn't need to be
  // While it does need to be upgraded, it tracks the (sole) release channel of its SingleBeacon
  // That's what needs to be owned
  await auctionProxy.transferOwnership(frabric.address);
  // FrabricERC20 beacon and FRBC
  await erc20Beacon.transferOwnership(frabric.address);
  await frbc.transferOwnership(frabric.address);
  // Frabric proxy
  await proxy.transferOwnership(frabric.address);

  // Deploy the DEX router
  // Technically a periphery contract yet this script treats InitialFrabric as
  // the initial entire ecosystem, not just itself
  const router = await deployDEXRouter();

  return {
    auction,
    erc20Beacon,
    frbc,
    pair,
    proxy,
    frabric,
    router
  };
};

if (require.main === module) {
  (async () => {
    let usd = process.env.USD;
    let uniswap = process.env.UNISWAP;
    let genesis;

    if ((!usd) || (!uniswap)) {
      console.error("Only some environment variables were provide. Provide USD and the Uniswap v2 Router.");
      process.exit(1);
    }
    genesis = require("../genesis.json");

    const contracts = await module.exports(usd, uniswap, genesis);
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