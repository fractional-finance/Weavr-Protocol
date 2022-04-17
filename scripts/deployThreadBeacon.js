const hre = require("hardhat");
const { ethers } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;
  return await deployBeacon([2], await ethers.getContractFactory("Thread"));
};

if (require.main === module) {
  module.exports()
    .then(beacon => console.log("Thread Beacon: " + beacon.address))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
