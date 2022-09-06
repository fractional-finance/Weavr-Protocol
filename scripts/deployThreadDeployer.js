const { ethers, upgrades } = require("hardhat");

const deployBeaconProxy = require("./deployBeaconProxy.js");
const deployBeacon = require("./deployBeacon.js");
const deployCrowdfundProxy = require("./deployCrowdfundProxy.js");
const deployThreadBeacon = require("./deployThreadBeacon.js");
const deployTimelock = require("./deployTimelock.js");

module.exports = async (erc20Beacon, auction) => {
  const crowdfundProxy = await deployCrowdfundProxy();
  const threadBeacon = await deployThreadBeacon();
  const timelock = await deployTimelock();

  const ThreadDeployer = await ethers.getContractFactory("ThreadDeployer");
  const proxy = await deployBeacon("single", ThreadDeployer)

  const threadDeployer = await deployBeaconProxy(proxy.address, ThreadDeployer, [crowdfundProxy.address, erc20Beacon, threadBeacon.address, auction, timelock.address]);

  // Transfer ownership of the timelock to the ThreadDeployer
  await (await timelock.transferOwnership(threadDeployer.address)).wait();

  return { crowdfundProxy, threadBeacon, timelock, proxy, threadDeployer };
};
