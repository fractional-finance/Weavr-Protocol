const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = async (usdc, bondToken) => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const Bond = await ethers.getContractFactory("Bond");
  const proxy = await deployBeacon(
    [],
    Bond,
    await ethers.getContractFactory("SingleBeacon")
  );

  const bond = await upgrades.deployBeaconProxy(
    proxy,
    Bond,
    [usdc, bondToken]
  );

  return { proxy, bond };
};

if (require.main === module) {
  module.exports("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")
    .then(contracts => {
      console.log("Proxy: " + contracts.proxy.address);
      console.log("Bond:  " + contracts.bond.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
