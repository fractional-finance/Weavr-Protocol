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
    let tx = await dex.sell(100, 10);
    const newBalance = (await dex.balanceOf.call(accounts[0]))

    assert.equal(newBalance, oldBalance - 100, "Sell order did not update balance")
    assert.equal(tx.logs[2].event, "NewSellOrder", "Incorrect event")
    assert.equal(tx.logs[3].event, "OrderIncrease", "Incorrect event")
  });
  
  it("should support placing multiple buy orders", async () => {
    const amount = 1;
    const oneEtherInWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneEtherInWei);
    const numBuys = 5;
    
    let tx;
    for (let i = 0; i < numBuys; i++) {
      tx = await dex.buy(amount, price, {value: oneEtherInWei});
    }

    let orderQuantity = (await dex.getOrderQuantity(price))
    assert.equal(orderQuantity, numBuys, "Buy order did not update balance")
    assert.equal(tx.logs[0].event, "OrderIncrease", "Unexpected event emitted")
  });
  
  it("should support fully filling sell order", async () => {
    const oneEtherInWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneEtherInWei);
    const amount = 5;
    
    let tx = await dex.sell(amount, price);
    
    let orderQuantity = (await dex.getOrderQuantity(price))
    let balance = (await dex.getEthBalance(accounts[0]))
    assert.equal(orderQuantity, 0, "Order quantity did not update balance")
    assert.equal(balance, price * 5, "Ethereum balance did not update")
  });
  
  it("should support partially filled sell orders", async () => {
    const amount = 1;
    const oneEthereInWei = web3.utils.toWei("1");
    const price = web3.utils.toBN(oneEthereInWei);
    const numBuys = 5;
    let oldBalance = (await dex.getEthBalance(accounts[0]))

    for (let i = 0; i < numBuys; i++) {
      await dex.buy(amount, price, {value: oneEthereInWei});
    }

    const sellAmount = 4
    await dex.sell(sellAmount, price);

    let orderQuantity = (await dex.getOrderQuantity(price))
    let balance = (await dex.getEthBalance(accounts[0]))
    assert.equal(orderQuantity, numBuys - sellAmount, "Order quantity did not update balance")
    assert.equal(balance - oldBalance, price * sellAmount, "Ethereum balance did not update")
  });

  it("should support placing multiple new sell orders", async () => {
    const amount = 1;
    const halfEtherInWei = web3.utils.toWei("0.5");
    const price = web3.utils.toBN(halfEtherInWei);
    let numSells = 3;
    
    let tx;
    tx = await dex.sell(amount, price);
    for (let i = 0; i < numSells; i++) {
      await dex.sell(amount, price);
    }

    let orderQuantity = (await dex.getOrderQuantity(price))
    assert.equal(orderQuantity, ++numSells, "Sell order did not update balance")
    assert.equal(tx.logs[2].event, "NewSellOrder", "Unexpected event emitted")
    assert.equal(tx.logs[3].event, "OrderIncrease", "Unexpected event emitted")
  });
  
  it("should support placing partially filling buy orders from sell", async () => {
    const buyAmount = 5;
    const halfEtherInWei = web3.utils.toWei("0.5");
    const price = web3.utils.toBN(halfEtherInWei);
    let oldOrderQuantity = (await dex.getOrderQuantity(price))
  
    let tx = await dex.buy(buyAmount, price, {value: buyAmount * price});

    let orderQuantity = (await dex.getOrderQuantity(price))
    assert.equal(orderQuantity, 1, "Buy order did not update quantity")
    assert.equal(tx.logs[0].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[4].event, "Transfer", "Unexpected event emitted")
    assert.equal(tx.logs[6].event, "OrderIncrease", "Unexpected event emitted")
  });

});
