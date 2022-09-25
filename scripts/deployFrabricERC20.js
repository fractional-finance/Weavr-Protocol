const {ethers, upgrades} = require("hardhat");

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
        console.log("auction deployed");
        await new Promise((res) => setTimeout(res, 5000));
        await auction.auction.supportsInterface("0xb7e72164")
        const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");
        await new Promise((res) => setTimeout(res, 5000));
        const erc20 = await deployBeaconProxy(
            beacon.address,
            FrabricERC20,
            args == null ? [] : [...args, auction.auction.address],
            args == null ? {initializer: false} : {}
        );
        return {auctionBeacon: auction.beacon, auction: auction.auction, erc20};
    },

    deployFRBC: async (usd) => {
        const beacon = await module.exports.deployBeacon();
        console.log("token beacon deployed");
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
        return {auctionBeacon: frbc.auctionBeacon, auction: frbc.auction, beacon, frbc: frbc.erc20};
    }
};
