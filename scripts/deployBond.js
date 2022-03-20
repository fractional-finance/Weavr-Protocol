const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async (usdc, bondToken) => {
  const Bond = await ethers.getContractFactory("Bond");
  const beacon = await deployBeacon(
    [],
    Bond,
    await ethers.getContractFactory("SingleBeacon")
  );

  const bond = await upgrades.deployBeaconProxy(
    beacon,
    Bond,
    [usdc, bondToken]
  );
  await bond.deployed();

  return { beacon, bond };
};

if (require.main === module) {
  if (!process.env.USDC) {
    process.env.USDC = "0x0000000000000000000000000000000000000000";
  }
  if (!process.env.BONDTOKEN) {
    // This will cause init to fail
    process.env.BONDTOKEN = "0x0000000000000000000000000000000000000000";
  }

  module.exports(process.env.USDC, process.env.BONDTOKEN)
    .then(contracts => {
      console.log("Bond Beacon: " + contracts.beacon.address);
      console.log("Bond: " + contracts.bond.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
