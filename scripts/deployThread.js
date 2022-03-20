const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = {
  deployThreadBeacon: async () => {
    return await deployBeacon([2], await ethers.getContractFactory("Thread"));
  },

  // Solely used for testing
  deployThread: async (beacon, args) => {
    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    const Thread = await ethers.getContractFactory("Thread");

    const thread = await upgrades.deployBeaconProxy(beacon, Thread, args);
    await thread.deployed();
    return thread;
  }
};

if (require.main === module) {
  module.exports.deployThreadBeacon()
    .then(beacon => {
      console.log("Thread Beacon: " + beacon.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
