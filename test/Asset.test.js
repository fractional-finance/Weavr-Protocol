const { assert } = require("chai");

require("chai")
  .use(require("bn-chai")(web3.utils.BN))
  .use(require("chai-as-promised"))
  .should();

let ERC20 = artifacts.require("ERC20Instance");

contract("Asset", (accounts) => {
  let asset;
  it("", async () => {
    asset = await Asset.new(
      nftPlatform,
      accounts[1],
      nft,
      100
    );
  });
});
