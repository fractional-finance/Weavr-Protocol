const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const deployAuction = require("./deployAuction.js");

module.exports = {
  deployBeacon: async () => {
    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    return await deployBeacon([2], await ethers.getContractFactory("FrabricERC20"));
  },

  // Solely used for testing (as exported, used in this file for deployFRBC)
  deploy: async (beacon, args) => {
    const auction = await deployAuction();
    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");
    const erc20 = await upgrades.deployBeaconProxy(
      beacon.address,
      FrabricERC20,
      args == null ? [] : [...args, auction.auction.address],
      args == null ? { initializer: false } : {}
    );
    return { auctionProxy: auction.proxy, auction: auction.auction, erc20 };
  },

  deployFRBC: async (usdc) => {
    const beacon = await module.exports.deployBeacon();
    const frbc = await module.exports.deploy(
      beacon,
      [
        "Frabric Token",
        "FRBC",
        // Supply is 0 as all distribution is via mint
        0,
        true,
        // Parent whitelist doesn't exist
        ethers.constants.AddressZero,
        usdc
      ]
    );
    return { auctionProxy: frbc.auctionProxy, auction: frbc.auction, beacon, frbc: frbc.erc20 };
  }
};

// These solely exist to test deployment scripts don't error when running,
// except for deployFrabric which actually will deploy the Frabric
if (require.main === module) {
  // Will disable the DEX functionality yet will deploy, which is all this block wants
  module.exports.deployFRBC(ethers.constants.AddressZero, ethers.constants.AddressZero)
    .then(contracts => {
      console.log("Auction Proxy:       " + contracts.auctionProxy.address);
      console.log("Auction:             " + contracts.auction.address);
      console.log("FrabricERC20 Beacon: " + contracts.beacon.address);
      console.log("FRBC:                " + contracts.frbc.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
