const hre = require("hardhat");
const { ethers, upgrades, waffle } = hre;

const { MerkleTree } = require("merkletreejs");

const u2SDK = require("@uniswap/v2-sdk");
const uSDK = require("@uniswap/sdk-core");

const deployBeacon = require("./deployBeacon.js");
const fERC20 = require("./deployFrabricERC20.js");
const deployDEXRouter = require("./deployDEXRouter.js");

module.exports = async (usdc, uniswap, genesis) => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const signer = (await ethers.getSigners())[0];

  const { auctionProxy, auction, beacon: erc20Beacon, frbc } = await fERC20.deployFRBC(usdc);
  await frbc.setWhitelisted(auction.address, ethers.utils.id("Auction"));

  // Deploy the Uniswap pair to get the bond token
  uniswap = new ethers.Contract(
    uniswap,
    require("@uniswap/v2-periphery/build/UniswapV2Router02.json").abi,
    signer
  );

  const pair = u2SDK.computePairAddress({
    factoryAddress: await uniswap.factory(),
    tokenA: new uSDK.Token(1, usdc, 18),
    tokenB: new uSDK.Token(1, frbc.address, 18)
  });
  // Whitelisting the pair to create the LP token does break the whitelist to some degree
  // We're immediately creating a wrapped derivative token with no transfer limitations
  // That said, it's a derivative subject to reduced profit potential and unusable as FRBC
  // Considering the critical role Uniswap plays in the Ethereum ecosystem, we accordingly accept this effect
  await frbc.setWhitelisted(pair, ethers.utils.id("Uniswap v2 FRBC-USDC Pair"));

  // Process the genesis
  let genesisList = [];
  for (const person in genesis) {
    await frbc.setWhitelisted(person, ethers.utils.id(genesis[person].info));
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

  usdc = new ethers.Contract(
    usdc,
    // Use the test Token contract as it'll supply IERC20
    (await ethers.getContractFactory("TestERC20")).interface,
    signer
  );
  await usdc.approve(uniswap.address, 10000);

  await uniswap.addLiquidity(
    usdc.address,
    frbc.address,
    10000, 10000, 10000, 10000,
    signer.address,
    // Pointless deadline yet validly formed
    Math.floor((Date.now() / 1000) + 30)
  );

  usdc = usdc.address;
  */

  // Remove self from the FRBC whitelist
  // While we have no powers over the Frabric, we can hold tokens
  // This is a mismatched state when we shouldn't have any powers except as needed to deploy
  frbc.remove(signer.address, 0);

  const InitialFrabric = await ethers.getContractFactory("InitialFrabric");
  const proxy = await deployBeacon(
    [],
    InitialFrabric,
    await ethers.getContractFactory("SingleBeacon")
  );

  const root = (
    new MerkleTree(
      genesisList.map((address) => address + "000000000000000000000000"),
      ethers.utils.keccak256,
      { sortPairs: true }
    )
  ).getHexRoot();

  const frabric = await upgrades.deployBeaconProxy(
    proxy.address,
    InitialFrabric,
    [
      frbc.address,
      genesisList,
      root.substr(2) ? root : "0x0000000000000000000000000000000000000000000000000000000000000000"
    ]
  );
  await frbc.setWhitelisted(frabric.address, ethers.utils.id("Frabric"));

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
    auction: auction.address,
    erc20Beacon: erc20Beacon.address,
    frbc: frbc.address,
    pair,
    proxy: proxy.address,
    frabric: frabric.address,
    router: router.address
  };
};

if (require.main === module) {
  (async () => {
    let usdc = process.env.USDC;
    let uniswap = process.env.UNISWAP;
    let genesis;

    if ((!usdc) || (!uniswap)) {
      console.error("Only some environment variables were provide. Provide USDC and the Uniswap v2 Router.");
      process.exit(1);
    }
    genesis = require("../genesis.json");

    const contracts = await module.exports(usdc, uniswap, genesis);
    console.log("Auction:           " + contracts.auction);
    console.log("ERC20 Beacon:      " + contracts.erc20Beacon);
    console.log("FRBC:              " + contracts.frbc);
    console.log("FRBC-USDC Pair:    " + contracts.pair);
    console.log("Initial Frabric:   " + contracts.frabric);
    console.log("DEX Router:        " + contracts.router);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
