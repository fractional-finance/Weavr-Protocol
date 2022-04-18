const { ethers, upgrades } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async (usdc, bondToken) => {
  const Bond = await ethers.getContractFactory("Bond");
  const proxy = await deployBeacon("single", Bond);

  const bond = await upgrades.deployBeaconProxy(
    proxy.address,
    Bond,
    [usdc, bondToken]
  );

  return { proxy, bond };
};
