const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const crowdfund = require("./deployCrowdfund.js");
const thread = require("./deployThread.js");

module.exports = async (erc20Beacon) => {
  const crowdfundProxy = await crowdfund.deployCrowdfundProxy();
  const threadBeacon = await thread.deployThreadBeacon();

  const ThreadDeployer = await ethers.getContractFactory("ThreadDeployer");
  const beacon = await deployBeacon(
    [],
    ThreadDeployer,
    await ethers.getContractFactory("SingleBeacon")
  );

  const threadDeployer = await upgrades.deployBeaconProxy(
    beacon,
    ThreadDeployer,
    [crowdfundProxy.address, erc20Beacon, threadBeacon.address]
  );
  await threadDeployer.deployed();

  return {
    beacon,
    crowdfundProxy,
    threadBeacon,
    threadDeployer
  };
};

if (require.main === module) {
  if (!process.env.FRABRIC) {
    process.env.FRABRIC = "0x0000000000000000000000000000000000000000";
  }
  if (!process.env.ERC20BEACON) {
    process.env.ERC20BEACON = "0x0000000000000000000000000000000000000000";
  }

  module.exports(process.env.FRABRIC, process.env.ERC20BEACON)
    .then(contracts => {
      console.log("ThreadDeployer Beacon: " + contracts.beacon.address);
      console.log("Crowdfund Proxy: " + contracts.crowdfundProxy.address);
      console.log("Thread Beacon: " + contracts.threadBeacon.address);
      console.log("ThreadDeployer: " + contracts.threadDeployer.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
