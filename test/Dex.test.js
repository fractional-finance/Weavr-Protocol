const { assert } = require("chai");

require("chai")
  .use(require("bn-chai")(web3.utils.BN))
  .use(require("chai-as-promised"))
  .should();

let StubbedDex = artifacts.require("StubbedDex");

contract("IntegratedLimitOrderDex", (accounts) => {
  let dex;
  it("should mint tokens to test with", async () => {
    dex = await StubbedDex.new();
    (await dex.totalSupply.call()).should.be.eq.BN(await dex.balanceOf.call(accounts[0]));
    (await dex.totalSupply.call()).toString().should.be.equal("1000000000000000000");
    await dex.approve(dex.address, await dex.totalSupply.call());
  });

  it("should support placing sell orders", async () => {
    const oldBalance = (await dex.balanceOf.call(accounts[0]))
    await dex.sell(100, 10);
    const newBalance = (await dex.balanceOf.call(accounts[0]))
    assert.equal(newBalance, oldBalance - 100, "Sell order did not update balance")
  });
  
  it("should support placing multiple buy orders", async () => {
    const amount = 1;
    const oneWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneWei);
    const numBuys = 5;
    
    let tx;
    for (let i = 0; i < numBuys; i++) {
      tx = await dex.buy(amount, price, {value: oneWei});
    }

    let orderQuantity = (await dex.getOrderQuantity(price))
    assert.equal(orderQuantity, numBuys, "Buy order did not update balance")
    assert.equal(tx.logs[0].event, "OrderIncrease", "Unexpected event emitted")
  });

  it("should support fully filling sell order", async () => {
    const oneWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneWei);
    const amount = 5;

    await dex.sell(amount, price);

    let orderQuantity = (await dex.getOrderQuantity(price))
    let balance = (await dex.getEthBalance(accounts[0]))
    assert.equal(orderQuantity, 0, "Order quantity did not update balance")
    assert.equal(balance, price * 5, "Ethereum balance did not update")
  });
  
  it("should support partially filled sell orders", async () => {
    const amount = 1;
    const oneWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneWei);
    const numBuys = 5;
    let oldBalance = (await dex.getEthBalance(accounts[0]))

    for (let i = 0; i < numBuys; i++) {
      await dex.buy(amount, price, {value: oneWei});
    }

    const sellAmount = 4
    await dex.sell(sellAmount, price);

    let orderQuantity = (await dex.getOrderQuantity(price))
    let balance = (await dex.getEthBalance(accounts[0]))
    assert.equal(orderQuantity, numBuys - sellAmount, "Order quantity did not update balance")
    assert.equal(balance - oldBalance, price * sellAmount, "Ethereum balance did not update")
  });
});
