const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = {
  deployCrowdfundProxy: async () => {
    return await deployBeacon(
      [],
      await ethers.getContractFactory("Crowdfund"),
      await ethers.getContractFactory("SingleBeacon")
    );
  },

  // Solely used for testing
  deployCrowdfund: async (beacon, args) => {
    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    const Crowdfund = await ethers.getContractFactory("Crowdfund");
    const crowdfund = await upgrades.deployBeaconProxy(beacon, Crowdfund, args);
    await crowdfund.deployed();
    return crowdfund;
  }
};

if (require.main === module) {
  module.exports.deployCrowdfundBeacon()
    .then(beacon => {
      console.log("Crowdfund Beacon: " + beacon.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
