const { ethers } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  return await deployBeacon(2, await ethers.getContractFactory("Thread"));
};
