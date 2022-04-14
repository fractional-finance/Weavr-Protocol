const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  // Run compile if it hasn't been run already
  // Prevents a print statement of "Nothing to compile" from repeatedly appearing
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const Auction = await ethers.getContractFactory("Auction");
  // Uses the term proxy for SingleBeacons because SingleBeacon effectively
  // nullifies Beacons back into normal, upgradeable proxies
  // We just have them to maintain a consistent API
  // Proxy isn't a technically correct term, as it's the instances which are proxies,
  // yet it works well enough
  const proxy = await deployBeacon(
    [],
    Auction,
    await ethers.getContractFactory("SingleBeacon")
  );

  const auction = await upgrades.deployBeaconProxy(proxy.address, Auction);

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
