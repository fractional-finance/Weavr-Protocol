const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  // Run compile if it hasn't been run already
  // Prevents a print statement of "Nothing to compile" from repeatedly appearing
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const Auction = await ethers.getContractFactory("Auction");
  const proxy = await deployBeacon(
    [],
    Auction,
    await ethers.getContractFactory("SingleBeacon")
  );

  const auction = await upgrades.deployBeaconProxy(proxy, Auction);
  await auction.deployed();

  return { proxy, auction };
};

if (require.main === module) {
  module.exports()
    .then(contracts => {
      console.log("Proxy:   " + contracts.proxy.address);
      console.log("Auction: " + contracts.auction.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
