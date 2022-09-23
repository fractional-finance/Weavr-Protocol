const { ethers, upgrades } = require("hardhat");

const deployBeaconProxy = require("./deployBeaconProxy.js");
const deployBeacon = require("./deployBeacon.js");
const deployAuction = require("./deployAuction.js");

module.exports = {
  deployBeacon: async () => {
    return await deployBeacon(2, await ethers.getContractFactory("FrabricERC20"));
  },

  // Solely used for testing (as exported, used in this file for deployFRBC)
  deploy: async (beacon, args) => {
    const auction = await deployAuction();
    console.log("deployed auction")
    await new Promise((res) => setTimeout(res, 5000));
    await auction.auction.supportsInterface("0xb7e72164")
      await new Promise((res) => setTimeout(res, 5000));
    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");
    const erc20 = await deployBeaconProxy(beacon.address, FrabricERC20, args == null ? [] : [...args, auction.auction.address], args == null ? { initializer: false } : {});
    console.log("deployed FRBC Beacon Proxy")
    return { auctionBeacon: auction.beacon, auction: auction.auction, erc20 };
  },

  deployWEAV: async (usd) => {
      console.log("about to deploy FRBC beacon")
    const beacon = await module.exports.deployBeacon();
    console.log("deployed frbc beacon")
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
    return { auctionBeacon: frbc.auctionBeacon, auction: frbc.auction, beacon, frbc: frbc.erc20 };
  }
};
