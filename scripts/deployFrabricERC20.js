const { ethers, upgrades } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");
const deployAuction = require("./deployAuction.js");

module.exports = {
  deployBeacon: async () => {
    return await deployBeacon(2, await ethers.getContractFactory("FrabricERC20"));
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
    return { auctionProxy: auction.beacon, auction: auction.auction, erc20 };
  },

  deployFRBC: async (usd) => {
    const beacon = await module.exports.deployBeacon();
    const frbc = await module.exports.deploy(
      beacon,
      [
        "Weavr Token",
        "WEAV",
        // Supply is 0 as all distribution is via mint
        0,
        // Parent whitelist doesn't exist
        ethers.constants.AddressZero,
        usd
      ]
    );
    return { auctionProxy: frbc.auctionProxy, auction: frbc.auction, beacon, frbc: frbc.erc20 };
  }
};
