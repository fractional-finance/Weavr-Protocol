const hre = require("hardhat");
const { ethers } = hre;

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const timelock = await (await ethers.getContractFactory("Timelock")).deploy();
  await timelock.deployed();
  return timelock;
};

if (require.main === module) {
  module.exports()
    .then(timelock => {
      console.log("Timelock: " + timelock.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
