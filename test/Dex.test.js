const { assert } = require("chai");

require("chai")
  .use(require("bn-chai")(web3.utils.BN))
  .use(require("chai-as-promised"))
  .should();

let StubbedDex = artifacts.require("StubbedDex");

contract("StubbedDex", (accounts) => {
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
    assert.equal(tx.logs[2].args.price, 10, "Incorrect event")
    assert.equal(tx.logs[3].event, "OrderIncrease", "Incorrect event")
    assert.equal(tx.logs[3].args.sender, accounts[0], "Incorrect event")
    assert.equal(tx.logs[3].args.price, 10, "Incorrect event")
    assert.equal(tx.logs[3].args.amount, 100, "Incorrect event")
  });
  
  it("should support placing multiple buy orders", async () => {
    const price = web3.utils.toWei("1");
    const numBuys = 5;
    
    let tx;
    for (let i = 0; i < numBuys; i++) {
      tx = await dex.buy(1, price, {value: price});
    }

    let orderQuantity = (await dex.getOrderQuantity(price));
    assert.equal(orderQuantity, numBuys, "Buy order did not update balance");
    assert.equal(tx.logs[0].event, "OrderIncrease", "Unexpected event emitted");
    assert.equal(tx.logs[0].args.price, price, "Unexpected price from event emitted");
    assert.equal(tx.logs[0].args.amount, 1, "Unexpected amount from event emitted");
    assert.equal(tx.logs[0].args.sender, accounts[0], "Unexpected sender from event emitted");
  });
  
  it("should support fully filling sell order", async () => {
    const price = web3.utils.toWei("1");
    const amount = 5;
    
    let tx = await dex.sell(amount, price);
    
    let orderQuantity = (await dex.getOrderQuantity(price))
    let balance = (await dex.getEthBalance(accounts[0]))
    assert.equal(orderQuantity, 0, "Order quantity did not update balance")
    assert.equal(balance, price * 5, "Ethereum balance did not update")
  });
  
  it("should support partially filled sell orders", async () => {
    const amount = 1;
    const price = web3.utils.toWei("1");
    const numBuys = 5;
    let oldBalance = (await dex.getEthBalance(accounts[0]))

    for (let i = 0; i < numBuys; i++) {
      await dex.buy(amount, price, {value: price});
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
    const price = web3.utils.toWei("2");
    let numSells = 4;
    
    let tx;
    for (let i = 0; i < numSells; i++) {
      if (i == 0) {
        tx = await dex.sell(amount, price);
      } else {
        await dex.sell(amount, price);
      }
    }
    let orderQuantity = (await dex.getOrderQuantity(price))

    assert.equal(orderQuantity, numSells, "Sell order did not update balance")
    assert.equal(tx.logs[2].event, "NewSellOrder", "Unexpected event emitted")
    assert.equal(tx.logs[3].event, "OrderIncrease", "Unexpected event emitted")
  });
  
  it("should support placing partially filling buy orders from sell", async () => {
    const buyAmount = 5;
    const price = web3.utils.toWei("2");
  
    let tx = await dex.buy(buyAmount, price, {value: buyAmount * price});
    let orderQuantity = (await dex.getOrderQuantity(price))

    assert.equal(orderQuantity, 1, "Buy order did not update quantity")
    assert.equal(tx.logs[0].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[0].args.sender, accounts[0], "Unexpected sender from event emitted")
    assert.equal(tx.logs[0].args.recipient, accounts[0], "Unexpected recipient from event emitted")
    assert.equal(tx.logs[0].args.amount, buyAmount, "Unexpected amount from event emitted")
    assert.equal(tx.logs[0].args.price, price, "Unexpected price from event emitted")
    assert.equal(tx.logs[1].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[1].args.sender, accounts[0], "Unexpected sender from event emitted")
    assert.equal(tx.logs[1].args.recipient, accounts[0], "Unexpected recipient from event emitted")
    assert.equal(tx.logs[1].args.price, price, "Unexpected price from event emitted")
    assert.equal(tx.logs[1].args.amount, buyAmount, "Unexpected amount from event emitted")
    assert.equal(tx.logs[2].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[3].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[4].event, "Transfer", "Unexpected event emitted")
    assert.equal(tx.logs[4].args.to, accounts[0], "Unexpected recipient from event emitted")
    assert.equal(tx.logs[5].event, "NewBuyOrder", "Unexpected event emitted")
    assert.equal(tx.logs[5].args.price, price, "Unexpected price from event emitted")
    assert.equal(tx.logs[6].event, "OrderIncrease", "Unexpected event emitted")
    assert.equal(tx.logs[6].args.sender, accounts[0], "Unexpected sender from event emitted")
    assert.equal(tx.logs[6].args.price, price, "Unexpected price from event emitted")
    assert.equal(tx.logs[6].args.amount, buyAmount, "Unexpected amount from event emitted")
  });
  
  it("should support sell/buy pair across multiple account", async () => {
    const amount = 1;
    const price = web3.utils.toWei("3");
    const numBuys = 5;
    let oldTokenBalance = (await dex.balanceOf.call(accounts[1]))
    
    
    await dex.sell(numBuys, price);
    let tx;
    for (let i = 0; i < numBuys; i++) {
      tx = await dex.buy(amount, price, {from: accounts[1], value: price * amount});
    }
    
    let newTokenBalance = (await dex.balanceOf.call(accounts[1]))
    let orderQuantity = (await dex.getOrderQuantity(price))

    assert.equal(oldTokenBalance, 0, "Should have initially a token balance of 0")
    assert.equal(newTokenBalance, numBuys, "Token balance did not update")
    assert.equal(orderQuantity, 0, "Order quantity did not update balance")
    assert.equal(tx.logs[0].event, "Filled", "Unexpected event emitted")
    assert.equal(tx.logs[0].args.sender, accounts[1], "Unexpected sender from event emitted")
    assert.equal(tx.logs[0].args.recipient, accounts[0], "Unexpected recipient from event emitted")
    assert.equal(tx.logs[0].args.amount, amount, "Unexpected amount from event emitted")
    assert.equal(tx.logs[0].args.price, price, "Unexpected price from event emitted")
  });
});

contract("IntegratedLimitOrderDex", (accounts) => {
  let dex;
  beforeEach(async () => {
    dex = await StubbedDex.new();
    (await dex.totalSupply.call()).should.be.eq.BN(await dex.balanceOf.call(accounts[0]));
    (await dex.totalSupply.call()).toString().should.be.equal("1000000000000000000");
    await dex.approve(dex.address, await dex.totalSupply.call());
  });

  it("should prevent cheating when buying", async () => {
    try {
      const price = web3.utils.toBN(web3.utils.toWei("1"));
      await dex.buy(1, price, {value: price.div(web3.utils.toBN(2))});
      assert.fail("should prevent cheating when value is not equal to amount purchased")
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Invalid message value"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });

  it("should prevent cheating when selling", async () => {
    try {
      const price = web3.utils.toBN(web3.utils.toWei("1"));
      await dex.sell(1, price, {from: accounts[1]});
      assert.fail("should prevent cheating when value is not equal to amount purchased")
    } catch(err) {
      const expectedError = "ERC20: transfer amount exceeds balance"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });
  
  it("should prevent overpaying when buying", async () => {
    try {
      const price = web3.utils.toBN(web3.utils.toWei("1"));
      await dex.buy(1, price, {value: price.mul(web3.utils.toBN(2))});
      assert.fail("should prevent overpaying when value is not equal to amount purchased")
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Invalid message value"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });
  
  it("should prevent 0 buy price", async () => {
    try {
      const price = web3.utils.toWei("0.5")
      await dex.buy(1, 0, {value: 2 * price});
      assert.fail("should prevent 0 buy price");
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Price is 0"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });

  it("should prevent 0 buy amount", async () => {
    try {
      const price = web3.utils.toWei("0.5")
      await dex.buy(0, price, {value: 2 * price});
      assert.fail("should prevent 0 buy amount");
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Amount is 0"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });
  
  it("should prevent 0 sell price", async () => {
    try {
      await dex.sell(1, 0);
      assert.fail("should prevent 0 buy price");
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Price is 0"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });

  it("should prevent 0 sell amount", async () => {
    try {
      const price = web3.utils.toWei("0.5")
      await dex.buy(0, price);
      assert.fail("should prevent 0 buy amount");
    } catch(err) {
      const expectedError = "IntegratedLimitOrderDex: Amount is 0"
      const actualError = err.reason;
      assert.equal(actualError, expectedError, "should not be permitted")
    }
  });
});