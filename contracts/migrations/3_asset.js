const Platform = artifacts.require("Platform");

module.exports = async function (deployer, _, accounts) {
  let platform = await Platform.deployed();
  let nft = (await platform.createNFT("Test Asset")).logs[0].args.tokenId;
  let asset = (await platform.deployAsset(0, accounts[0], nft, 100, "FRABRIC-TEST")).logs[1].args.assetContract;
  await platform.safeTransferFrom(accounts[0], asset, nft);
};
