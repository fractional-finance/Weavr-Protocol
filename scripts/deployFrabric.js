const hre = require("hardhat");
const { ethers } = hre;

const deployBond = require("./deployBond.js");
const deployThreadDeployer = require("./deployThreadDeployer.js");

module.exports = async (auction, erc20Beacon, usd, pair, initial_frabric) => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const { proxy: bondProxy, bond } = await deployBond(usd, pair);
  const {
    crowdfundProxy,
    threadBeacon,
    proxy: threadDeployerProxy,
    threadDeployer
  } = await deployThreadDeployer(erc20Beacon, auction);

  const frabric = (await (await ethers.getContractFactory("Frabric")).deploy()).address;

  // Transfer ownership of everything to the Frabric (the actual proxy)
  // Bond proxy and bond
  await (await bondProxy.transferOwnership(frabric)).wait();
  await (await bond.transferOwnership(frabric)).wait();
  // Crowdfund proxy
  await (await crowdfundProxy.transferOwnership(frabric)).wait();
  // Thread beacon
  await (await threadBeacon.transferOwnership(frabric)).wait();
  // ThreadDeployer proxy and ThreadDeployer
  await (await threadDeployerProxy.transferOwnership(frabric)).wait();
  await (await threadDeployer.transferOwnership(frabric)).wait();

  return {
    threadDeployer,
    bond,
    frabricCode: frabric
  };
};

if (require.main === module) {
  (async () => {
    let auction = process.env.AUCTION;
    let erc20Beacon = process.env.ERC20_BEACON;
    let usd = process.env.USD;
    let pair = process.env.PAIR;
    let frabric = process.env.FRABRIC;

    if ((!auction) || (!erc20Beacon) || (!usd) || (!pair) || (!frabric)) {
      console.error(
        "Only some environment variables were provide. Provide the ERC20 Beacon, " +
        "the Auction contract, USD, the Uniswap Pair, and the Initial Frabric."
      );
      process.exit(1);
    }

    const contracts = await module.exports(auction, erc20Beacon, usd, pair, frabric);
    console.log("Thread Deployer: " + contracts.threadDeployer.address);
    console.log("Bond:            " + contracts.bond.address);
    console.log("Frabric Code:    " + contracts.frabricCode);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });
}
