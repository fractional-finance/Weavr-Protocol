const Platform = artifacts.require("Platform");
const Asset = artifacts.require("Asset");

module.exports = async function (deployer, _, accounts) {
  let platform = await Platform.deployed();
  let nft = (await platform.createNFT("Test Asset")).logs[0].args.tokenId;
  let asset = (await platform.deployAsset(0, accounts[0], nft, 100, "FRABRIC-TEST")).logs[1].args.assetContract;
  await platform.safeTransferFrom(accounts[0], asset, nft);

  // Setup code for the demo
  asset = await Asset.at(asset);
  await asset.globallyAccept();

  await asset.approve(asset.address, 44);
  await asset.sell(44, 50);

  await asset.buy(20, 50, { from: accounts[1], value: 20 * 50 });
  await asset.proposePaper("Demo proposal", { from: accounts[1] });
  await asset.voteYes(0);
};
