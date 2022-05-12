const { ethers } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => await deployBeacon(2, await ethers.getContractFactory("Thread"));
