const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = {
  deployFrabricERC20Beacon: async () => {
    return await deployBeacon([2], await ethers.getContractFactory("FrabricERC20"));
  },

  // Solely used for testing (as exported, used in this file for the intended to be used deployFRBC)
  deployFrabricERC20: async (beacon, args) => {
    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");

    const frbc = await upgrades.deployBeaconProxy(beacon, FrabricERC20, args);
    await frbc.deployed();
    return frbc;
  },

  deployFRBC: async (usdc) => {
    let result = { beacon: await module.exports.deployFrabricERC20Beacon() };
    result.frbc = await module.exports.deployFrabricERC20(
      result.beacon,
      [
        "Frabric Token",
        "FRBC",
        0,
        true,
        "0x0000000000000000000000000000000000000000",
        usdc
      ]
    );
    return result;
  }
};

if (require.main === module) {
  if (!process.env.USDC) {
    process.env.USDC = "0x0000000000000000000000000000000000000000";
  }

  module.exports.deployFRBC(process.env.USDC)
    .then(contracts => {
      console.log("FrabricERC20 Beacon: " + contracts.beacon.address);
      console.log("FRBC: " + contracts.frbc.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
