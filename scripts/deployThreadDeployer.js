const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");
const deployCrowdfundProxy = require("./deployCrowdfundProxy.js");
const thread = require("./deployThread.js");
const deployTimelock = require("./deployTimelock.js");

module.exports = async (erc20Beacon, auction) => {
  const crowdfundProxy = await deployCrowdfundProxy();
  const threadBeacon = await thread.deployBeacon();
  const timelock = await deployTimelock();

  const ThreadDeployer = await ethers.getContractFactory("ThreadDeployer");
  const proxy = await deployBeacon(
    [],
    ThreadDeployer,
    await ethers.getContractFactory("SingleBeacon")
  );

  const threadDeployer = await upgrades.deployBeaconProxy(
    proxy.address,
    ThreadDeployer,
    [crowdfundProxy.address, erc20Beacon, threadBeacon.address, auction, timelock.address]
  );

  // Transfer ownership of the timelock to the ThreadDeployer
  await timelock.transferOwnership(threadDeployer.address);

  return { crowdfundProxy, threadBeacon, timelock, proxy, threadDeployer };
};

if (require.main === module) {
  // See commentary in deployFrabricERC20 on this behavior
  module.exports(ethers.constants.AddressZero, ethers.constants.AddressZero)
    .then(contracts => {
      console.log("Crowdfund Proxy:      " + contracts.crowdfundProxy.address);
      console.log("Thread Beacon:        " + contracts.threadBeacon.address);
      console.log("Timelock:             " + contracts.timelock.address);
      console.log("ThreadDeployer Proxy: " + contracts.proxy.address);
      console.log("ThreadDeployer:       " + contracts.threadDeployer.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
