const hre = require("hardhat");
const { ethers } = hre;

const deployBond = require("./deployBond.js");
const deployThreadDeployer = require("./deployThreadDeployer.js");

module.exports = async (auction, erc20Beacon, usdc, pair, frabric) => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const { proxy: bondProxy, bond } = await deployBond(usdc, pair);
  const {
    crowdfundProxy,
    threadBeacon,
    proxy: threadDeployerProxy,
    threadDeployer
  } = await deployThreadDeployer(erc20Beacon, auction);

  const frabricCode = (await (await ethers.getContractFactory("Frabric")).deploy()).address;

  // Transfer ownership of everything to the Frabric (the actual proxy)
  // Bond proxy and bond
  await bondProxy.transferOwnership(frabric);
  await bond.transferOwnership(frabric);
  // Crowdfund proxy
  await crowdfundProxy.transferOwnership(frabric);
  // Thread beacon
  await threadBeacon.transferOwnership(frabric);
  // ThreadDeployer proxy and ThreadDeployer
  await threadDeployerProxy.transferOwnership(frabric);
  await threadDeployer.transferOwnership(frabric);

  return {
    threadDeployer: threadDeployer.address,
    bond: bond.address,
    frabricCode
  };
};

if (require.main === module) {
  (async () => {
    let auction = process.env.AUCTION;
    let erc20Beacon = process.env.ERC20_BEACON;
    let usdc = process.env.USDC;
    let pair = process.env.PAIR;
    let frabric = process.env.FRABRIC;

    if ((!auction) || (!erc20Beacon) || (!usdc) || (!pair) || (!frabric)) {
      console.error(
        "Only some environment variables were provide. Provide the ERC20 Beacon, " +
        "the Auction contract, USDC, the Uniswap Pair, and the Initial Frabric."
      );
      process.exit(1);
    }

    const contracts = await module.exports(auction, erc20Beacon, usdc, pair, frabric);
    console.log("Thread Deployer: " + contracts.threadDeployer.address);
    console.log("Bond:            " + contracts.bond.address);
    console.log("Frabric Code:    " + contracts.frabricCode.address);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
