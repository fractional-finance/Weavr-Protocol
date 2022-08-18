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
    console.log("deployed auction");
    console.log(new ethers.providers.Web3Provider(network.provider));
    console.log("code ", (await (new ethers.providers.Web3Provider(network.provider)).getCode(auction.auction.address)).length);
    console.log(await auction.auction.supportsInterface("0xb7e72164"));
    await new Promise((res) => setTimeout(res, 5000));
    console.log(await auction.auction.supportsInterface("0xb7e72164"));
    await new Promise((res) => setTimeout(res, 5000));
    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");
    const erc20 = await upgrades.deployBeaconProxy(
      beacon.address,
      FrabricERC20.nativeContractFactory,
      args == null ? [] : [...args, auction.auction.address],
      args == null ? { initializer: false } : {}
    );
    console.log("deployed beacon proxy")
    return { auctionProxy: auction.proxy, auction: auction.auction, erc20 };
  },

  deployFRBC: async (usd) => {
    const beacon = await module.exports.deployBeacon();
    console.log("deployed beacon")
    const frbc = await module.exports.deploy(
      beacon,
      [
        "Frabric Token",
        "FRBC",
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
