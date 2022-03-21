const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const crowdfund = require("./deployCrowdfund.js");
const thread = require("./deployThread.js");

module.exports = async (erc20Beacon) => {
  const crowdfundProxy = await crowdfund.deployCrowdfundProxy();
  const threadBeacon = await thread.deployThreadBeacon();

  const ThreadDeployer = await ethers.getContractFactory("ThreadDeployer");
  const proxy = await deployBeacon(
    [],
    ThreadDeployer,
    await ethers.getContractFactory("SingleBeacon")
  );

  const threadDeployer = await upgrades.deployBeaconProxy(
    proxy,
    ThreadDeployer,
    [crowdfundProxy.address, erc20Beacon, threadBeacon.address]
  );
  await threadDeployer.deployed();

  return { proxy, crowdfundProxy, threadBeacon, threadDeployer };
};

if (require.main === module) {
  // See commentary in deployFrabricERC20 on this behavior
  module.exports("0x0000000000000000000000000000000000000000")
    .then(contracts => {
      console.log("ThreadDeployer Proxy: " + contracts.proxy.address);
      console.log("Crowdfund Proxy:      " + contracts.crowdfundProxy.address);
      console.log("Thread Beacon:        " + contracts.threadBeacon.address);
      console.log("ThreadDeployer:       " + contracts.threadDeployer.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
