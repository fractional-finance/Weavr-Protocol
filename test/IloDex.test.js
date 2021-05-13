require("chai")
  .use(require("bn-chai")(web3.utils.BN))
  .use(require("chai-as-promised"))
  .should();

let IloDexERC20 = artifacts.require("IloDexERC20");

contract("IntegratedLimitOrderDex", (accounts) => {
  let dex;
  it("should mint tokens to test with", async () => {
    dex = await IloDexERC20.new();
    (await dex.totalSupply.call()).should.be.eq.BN(await dex.balanceOf.call(accounts[0]));
    (await dex.totalSupply.call()).toString().should.be.equal("1000000000000000000");
    await dex.approve(dex.address, await dex.totalSupply.call());
  });

  it("should support placing sell orders", async () => {
    await dex.sell(100, 10);
  });
});
