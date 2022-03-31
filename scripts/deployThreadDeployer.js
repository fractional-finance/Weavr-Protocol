const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const crowdfund = require("./deployCrowdfund.js");
const thread = require("./deployThread.js");
const deployTimelock = require("./deployTimelock.js");

module.exports = async (erc20Beacon, auction) => {
  const crowdfundProxy = await crowdfund.deployCrowdfundProxy();
  const threadBeacon = await thread.deployThreadBeacon();
  const timelock = await deployTimelock();

  const ThreadDeployer = await ethers.getContractFactory("ThreadDeployer");
  const proxy = await deployBeacon(
    [],
    ThreadDeployer,
    await ethers.getContractFactory("SingleBeacon")
  );

  const threadDeployer = await upgrades.deployBeaconProxy(
    proxy,
    ThreadDeployer,
    [crowdfundProxy.address, erc20Beacon, threadBeacon.address, auction, timelock.address]
  );
  await threadDeployer.deployed();

  // Transfer ownership of the timelock to the ThreadDeployer
  await timelock.transferOwnership(threadDeployer.address);

  return { proxy, crowdfundProxy, threadBeacon, threadDeployer };
};

if (require.main === module) {
  // See commentary in deployFrabricERC20 on this behavior
  module.exports("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")
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
