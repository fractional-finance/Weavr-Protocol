const { ethers, upgrades } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async (usd, bondToken) => {
  const Bond = await ethers.getContractFactory("Bond");
  const proxy = await deployBeacon("single", Bond);

  const bond = await upgrades.deployBeaconProxy(
      proxy.address,
      Bond,
      [usd, bondToken]
  );

  return { proxy, bond };
};
