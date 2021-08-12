const Platform = artifacts.require("Platform");
const AssetDeployer = artifacts.require("AssetDeployer");

module.exports = async function (deployer) {
  await deployer.deploy(Platform);
  await deployer.deploy(AssetDeployer);
  await (await Platform.deployed()).addAssetDeployer(AssetDeployer.address);
};
