const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async (usdc, bondToken) => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const Bond = await ethers.getContractFactory("Bond");
  const proxy = await deployBeacon(
    [],
    Bond,
    await ethers.getContractFactory("SingleBeacon")
  );

  const bond = await upgrades.deployBeaconProxy(
    proxy,
    Bond,
    [usdc, bondToken]
  );

  return { proxy, bond };
};

// Doesn't have a main block to check this script's deployment validity
// Doing so requires a Uniswap deployment which is out of scope for writing a basic check
