const { ethers } = require("hardhat");

module.exports = async () => await (await ethers.getContractFactory("Timelock")).deploy();
