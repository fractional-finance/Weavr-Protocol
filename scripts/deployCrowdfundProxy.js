const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  return await deployBeacon(
    [],
    await ethers.getContractFactory("Crowdfund"),
    await ethers.getContractFactory("SingleBeacon")
  );
};

if (require.main === module) {
  module.exports()
    .then(proxy => console.log("Crowdfund Proxy: " + proxy.address))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
