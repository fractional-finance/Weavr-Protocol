const { ethers, upgrades } = require("hardhat");

const deployBeacon = require("./deployBeacon.js");

module.exports = async () => {
  const Auction = await ethers.getContractFactory("Auction");
  // Uses the term proxy for SingleBeacons because SingleBeacon effectively
  // nullifies Beacons back into normal, upgradeable proxies
  // We just have them to maintain a consistent API
  // Proxy isn't a technically correct term, as it's the instances which are proxies,
  // yet it works well enough
  const proxy = await deployBeacon("single", Auction);
  console.log("about to deploy auction beacon proxy")
  const auction = await upgrades.deployBeaconProxy(proxy.address, Auction.nativeContractFactory);
  console.log("deployed auction beacon proxy")
  return { proxy, auction };
};



if (require.main === module) {
  (async () => {
    let {proxy, auction} = await module.exports();
    console.log("Proxy: " + proxy.address);
    console.log("Auction: " + auction.address);
  })().catch(error => {
    console.error(error);
    process.exit(1);
  });

}