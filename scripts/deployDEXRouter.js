const hre = require("hardhat");
const { ethers } = hre;

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const router = await (await ethers.getContractFactory("DEXRouter")).deploy();
  await router.deployed();
  return router;
};
