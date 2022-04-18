const { ethers } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  return await deployBeacon("single", await ethers.getContractFactory("Crowdfund"));
};
