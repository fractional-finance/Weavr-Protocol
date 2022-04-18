const { ethers } = require("hardhat");

module.exports = async () => {
  return await (await ethers.getContractFactory("DEXRouter")).deploy();
};
