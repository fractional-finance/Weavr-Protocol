const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const FrabricERC20 = require("./deployFrabricERC20.js");
const deployBond = require("./deployBond.js");
const deployThreadDeployer = require("./deployThreadDeployer.js");

module.exports = async (usdc, uniswapRouter, kyc) => {

  const { beacon: erc20Beacon, frbc } = await FrabricERC20.deployFRBC(process.env.USDC);

  // Deploy the Uniswap pair to get the bond token
  // TODO

  //const { bond } = await deployBond(bondToken.address);
  const bond = usdc;
  const { threadDeployer } = await deployThreadDeployer(erc20Beacon.address);

  const beacon = await deployBeacon(
    [],
    await ethers.getContractFactory("Frabric"),
    await ethers.getContractFactory("SingleBeacon")
  );

  const Frabric = await ethers.getContractFactory("Frabric");
  const frabric = await upgrades.deployBeaconProxy(beacon, Frabric, [frbc.address, kyc, bond, threadDeployer.address]);
  await frabric.deployed();

  // Now that all contracts are deployed, set the whitelist, mint balances, and transfer ownerships
  // TODO

  return {
    frbc,
    //bondToken,
    bond,
    threadDeployer,
    beacon,
    frabric
  };
};

if (require.main === module) {
  if (!process.env.USDC) {
    process.env.USDC = "0x0000000000000000000000000000000000000000";
  }
  if (!process.env.UNISWAP) {
    process.env.UNISWAPROUTER = "0x0000000000000000000000000000000000000000";
  }
  if (!process.env.KYC) {
    process.env.KYC = "0x0000000000000000000000000000000000000000";
  }
  module.exports(process.env.USDC, process.env.UNISWAP, process.env.KYC)
    .then(contracts => {
      console.log("FRBC: " + contracts.frbc.address);
      //console.log("Bond Token: " + contracts.bondToken.address);
      console.log("Bond: " + contracts.bond);
      console.log("Thread Deployer: " + contracts.threadDeployer.address);
      console.log("Beacon: " + contracts.beacon.address);
      console.log("Frabric: " + contracts.frabric.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
