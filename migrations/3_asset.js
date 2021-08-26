const Platform = artifacts.require("Platform");
const Asset = artifacts.require("Asset");


// Demo params

const demo = {
  assets: [
    {
      nft: {
        dataURI: 'ipfs://Qmb8gunfwJEVBACGg9ZPvj3Mkbbj2SL1cZZLMAcmAP4hEC'
      },
      erc20: {
        symbol: 'FBRA420',
        totalSupply: 1000000
      }
    }
  ],
  scenario: {
    initialAssetValue: 5 * Math.pow(10, 18), // The entire asset is worth this much wei at the beginning
    valueIncreaseStep: 0.02, // After every purchase the value is increased by this percent on every order
    numberOfSellOrders: 6, // Number of sell orders pre-posted by the 1st actor
    numberOfSharesPerOrder: 100000, // Number of shares per every order posted (this is how many has to be purchased via the UI)
    numberOfBuyOrders: 2, // Number of buy orders pre-posted by the 2nd actor
    proposals: [ // Proposals created after initial share exchange
      {
        dataURI: 'ipfs://QmRWCC5AXeHuooknzQrJyeCq41nsCxReQRNxoFf9JSZotE'
      }
    ]
  }
}

module.exports = async function (deployer, _, accounts) {
  // Pick any assets and addresses from your wallet of preference

  let demoAsset0 = demo.assets[0];
  let demoAccounts = [
    accounts[1],
    accounts[2],
    accounts[3]
  ];

  let platform = await Platform.deployed();
  let nft = (await platform.createNFT(demoAsset0.nft.dataURI)).logs[0].args.tokenId;
  let asset = (await platform.deployAsset(0, demoAccounts[0], nft, demoAsset0.erc20.totalSupply, demoAsset0.erc20.symbol)).logs[1].args.assetContract;
  await platform.safeTransferFrom(demoAccounts[0], asset, nft);

  // Demo script

  asset = await Asset.at(asset);
  await asset.globallyAccept();

  const initialPricePerShare = demo.scenario.initialAssetValue / demoAsset0.erc20.totalSupply

  // First actor is selling their shares in `i` rounds

  await asset.approve(asset.address, demoAsset0.erc20.totalSupply, { from: demoAccounts[0] });
  for (var i = 0; i < demo.scenario.numberOfSellOrders; i++) {
    let assetPricePerShare = priceOfShareAtStep(initialPricePerShare, demo.scenario.valueIncreaseStep, i);
    await asset.sell(demo.scenario.numberOfSharesPerOrder, assetPricePerShare, { from: demoAccounts[0] });
  }

  // Second actor is buying some of the shares

  for (var i = 0; i < demo.scenario.numberOfBuyOrders; i++) {
    let assetPricePerShare = priceOfShareAtStep(initialPricePerShare, demo.scenario.valueIncreaseStep, i);
    await asset.buy(demo.scenario.numberOfSharesPerOrder, assetPricePerShare, { from: demoAccounts[1], value: demo.scenario.numberOfSharesPerOrder * assetPricePerShare });
  }

  // Second actor creates proposals
  
  for (var i = 0; i < demo.scenario.proposals.length; i++) {
    let proposalURI = demo.scenario.proposals[i].dataURI
    await asset.proposePaper(proposalURI, { from: demoAccounts[1] });
  }

  // First actor votes on the first proposal with their shares

  // await asset.voteYes(0, { from: demoAccounts[0] });
};

function priceOfShareAtStep(initialPrice, stepIncrease, step) {
  return Math.floor(initialPrice * Math.pow((1.00 + stepIncrease), step));
}
