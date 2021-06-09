const { assert } = require("chai");

require("chai")
  .use(require("bn-chai")(web3.utils.BN))
  .use(require("chai-as-promised"))
  .should();

let ERC20 = artifacts.require("ERC20Instance");

contract("Asset", (accounts) => {
  let superfluid;
  let asset;
  it("", async () => {
    superfluid = await deploySuperfluid(web3, accounts[0], (await ERC20.new(2, "USD Test", "USD")));
    asset = await Asset.new(
      nftPlatform,
      accounts[1],
      nft,
      100,
      superfluid.superfluid.options.address,
      superfluid.ida.options.address,
      superfluid.token.options.address
    );
  });
});
