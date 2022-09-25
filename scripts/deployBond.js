const { ethers, upgrades } = require("hardhat");

const deployBeaconProxy = require("./deployBeaconProxy.js");
const deployBeacon = require("./deployBeacon.js");

module.exports = async (usd, bondToken) => {
  const Bond = await ethers.getContractFactory("Bond");
  const proxy = await deployBeacon("single", Bond);

  const bond = await deployBeaconProxy(proxy.address, Bond, [usd, bondToken]);
  return { proxy, bond };
};