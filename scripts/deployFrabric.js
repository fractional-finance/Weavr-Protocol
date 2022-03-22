const hre = require("hardhat");
const { ethers, upgrades } = hre;

const u2SDK = require("@uniswap/v2-sdk");
const uSDK = require("@uniswap/sdk-core");

const deployBeacon = require("./deployBeacon.js");
const FrabricERC20 = require("./deployFrabricERC20.js");
const deployBond = require("./deployBond.js");
const deployThreadDeployer = require("./deployThreadDeployer.js");
const deployDEXRouter = require("./deployDEXRouter.js");

module.exports = async (usdc, uniswap, genesis, kyc) => {
  let signer = (await ethers.getSigners())[0];

  const { beacon: erc20Beacon, frbc } = await FrabricERC20.deployFRBC(usdc);

  // Deploy the Uniswap pair to get the bond token
  uniswap = new ethers.Contract(
    uniswap,
    require("@uniswap/v2-periphery/build/UniswapV2Router02.json").abi,
    signer
  );

  let pair = u2SDK.computePairAddress({
    factoryAddress: await uniswap.factory(),
    tokenA: new uSDK.Token(1, usdc, 18),
    tokenB: new uSDK.Token(1, frbc.address, 18)
  });
  await frbc.setWhitelisted(uniswap.address, ethers.utils.id("Uniswap v2 Router"));
  // Whitelisting the pair to create the LP token does break the whitelist to some degree
  // We're immediately creating a wrapped derivative token with no transfer limitations
  // That said, it's a derivative subject to reduced profit potential and unusable as FRBC
  // Considering the critical role Uniswap plays in the Ethereum ecosystem, we accordingly accept this effect
  await frbc.setWhitelisted(pair, ethers.utils.id("Uniswap v2 FRBC-USDC Pair"));

  // Process the genesis
  let genesisList = [];
  for (let person in genesis) {
    await frbc.setWhitelisted(person, ethers.utils.id(genesis[person].info));
    await frbc.mint(person, genesis[person].amount);
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

  // Create the pair now so the Bond contract can validate its bond token
  // If it wasn't for that validation, it'd be enough to just pass the address
  // Then whoever adds the initial liquidity would cause this to be created
  await (new ethers.Contract(
    await uniswap.factory(),
    require("@uniswap/v2-core/build/UniswapV2Factory.json").abi,
    signer
  )).createPair(usdc, frbc.address);

  // Remove self from the FRBC whitelist
  // While we have no powers over the Frabric, we can hold tokens
  // This is a mismatched state when we shouldn't have any powers except as needed to deploy
  frbc.setWhitelisted(signer.address, "0x0000000000000000000000000000000000000000000000000000000000000000");

  const { proxy: bondProxy, bond } = await deployBond(usdc, pair);
  const {
    proxy: threadDeployerProxy,
    crowdfundProxy,
    threadBeacon,
    threadDeployer
  } = await deployThreadDeployer(erc20Beacon.address);

  const proxy = await deployBeacon(
    [],
    await ethers.getContractFactory("Frabric"),
    await ethers.getContractFactory("SingleBeacon")
  );

  const Frabric = await ethers.getContractFactory("Frabric");
  const frabric = await upgrades.deployBeaconProxy(
    proxy,
    Frabric,
    [frbc.address, bond.address, threadDeployer.address, genesisList, kyc]
  );
  await frabric.deployed();
  await frbc.setWhitelisted(frabric.address, ethers.utils.id("Frabric"));

  // Transfer ownership of everything to the Frabric
  // FrabricERC20 beacon and FRBC
  await erc20Beacon.transferOwnership(frabric.address);
  await frbc.transferOwnership(frabric.address);
  // Crowdfund proxy
  await crowdfundProxy.transferOwnership(frabric.address);
  // Thread beacon
  await threadBeacon.transferOwnership(frabric.address);
  // ThreadDeployer proxy and self
  await threadDeployerProxy.transferOwnership(frabric.address);
  await threadDeployer.transferOwnership(frabric.address);
  // Bond proxy and self
  await bondProxy.transferOwnership(frabric.address);
  await bond.transferOwnership(frabric.address);
  // Frabric proxy
  await proxy.transferOwnership(frabric.address);

  // Deploy the DEX router
  // Technically a periphery contract yet this script treats Frabric as the entire ecosystem, not just itself
  const router = await deployDEXRouter();

  return {
    frbc,
    pair,
    bond,
    frabric,
    router
  };
};

if (require.main === module) {
  (async () => {
    let usdc = process.env.USDC;
    let uniswap = process.env.UNISWAP;
    let kyc = process.env.KYC;

    // Use test values if no environment variables were specified
    const variables = (usdc ? 1 : 0) + (uniswap ? 1 : 0) + (kyc ? 1 : 0);
    if (!variables) {
      process.hhCompiled ? null : await hre.run("compile");
      process.hhCompiled = true;

      const Token = await ethers.getContractFactory("TestERC20");
      usdc = await Token.deploy("USD Test", "USD");
      await usdc.deployed();
      usdc = usdc.address;

      uniswap = (await require("./deployUniswap.js")()).router.address;

      kyc = (await ethers.getSigners())[0].address;
    // If only some variables were specified, error accordingly
    } else if (variables != 3) {
      console.error("Only some environment variables were provide. Provide USDC, the Uniswap v2 Router, and KYC or none.");
      process.exit(1);
    }

    const contracts = await module.exports(usdc, uniswap, {}, kyc);
    console.log("FRBC:              " + contracts.frbc.address);
    console.log("Pair (Bond Token): " + contracts.pair);
    console.log("Bond:              " + contracts.bond.address);
    console.log("Frabric:           " + contracts.frabric.address);
    console.log("DEX Router:        " + contracts.router.address);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
