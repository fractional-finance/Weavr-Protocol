const { ethers } = require("hardhat");
const { expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { OrderType } = require("../common.js");

// Do not set below 100
// While it's theoretically fine to only fuzz on a single price point, and the
// higher level of interactions would create more complex situations, multiple
// price points will exist in the real world. Therefore, they should here
const FUZZ_ROUNDS = 100;

let signers, deployer, other;
let book = {}, usdBalances = {}, frbcBalances = {}, locked = {};
let usd, frbc;

function sold(address, price, amount) {
  frbcBalances[address] = frbcBalances[address].sub(amount);
  locked[address] = locked[address].sub(amount);
  usdBalances[address] = usdBalances[address] ? (
    usdBalances[address].add(amount.mul(price))
  ) : amount.mul(price);
}

async function bought(address, other, price, amount) {
  frbcBalances[address] = frbcBalances[address] ? (
    frbcBalances[address].add(amount)
  ) : amount;
  return [[frbc, "Transfer"], [other, address, await frbc.atomic(amount)]];
}

async function action(type, trader, price, amount) {
  let counter, method;
  if (type === OrderType.Buy) {
    counter = OrderType.Sell;
  } else {
    counter = OrderType.Buy;
  }

  if (type == OrderType.Sell) {
    locked[trader] = locked[trader] ? locked[trader].add(amount) : amount;
  }

  // Simulate the trade with our variables to get the events which should be emitted
  let events = [];
  let mutated = [trader];
  if (book.hasOwnProperty(price)) {
    if (book[price].type === counter) {
      for (let i = (book[price].orders.length - 1); i != -1; i--) {
        let order = book[price].orders[i];
        mutated.push(order.trader);

        let filled;
        if (amount.gte(order.amount)) {
          filled = order.amount;
          book[price].orders.pop();
        } else {
          filled = amount;
          book[price].orders[i].amount = order.amount.sub(filled);
        }
        events.push([[frbc, "Filled"], [trader, order.trader, price, filled]]);
        events.push(
          await bought(
            (type === OrderType.Buy) ? trader : order.trader,
            (type === OrderType.Buy) ? order.trader : trader,
            price,
            filled
          )
        );
        sold((type === OrderType.Sell) ? trader : order.trader, price, filled);

        amount = amount.sub(filled);
        if (amount.isZero()) {
          break;
        }
      }

      if (book[price].orders.length === 0) {
        delete book[price];
      }
    } else {
      book[price].orders.push({ trader, amount });
      events.push([[frbc, "OrderIncrease"], [trader, price, amount]]);
    }
  }

  if ((!book.hasOwnProperty(price)) && (!amount.eq(0))) {
    book[price] = {
      type: type,
      orders: [{ trader, amount }]
    };
    events.push([[frbc, "NewOrder"], [type, price]]);
    events.push([[frbc, "OrderIncrease"], [trader, price, amount]]);
  }

  return { events, mutated };
}

async function verify(price, tx, events, mutated) {
  for (let event of events) {
    await expect(tx).to.emit(...event[0]).withArgs(...event[1]);
  }

  for (let address of mutated) {
    if (usdBalances[address]) {
      expect(await frbc.tradeTokenBalances(address)).to.equal(usdBalances[address]);
    }
    if (frbcBalances[address]) {
      expect(await frbc.balanceOf(address)).to.equal(await frbc.atomic(frbcBalances[address]));
    }
    if (locked[address]) {
      expect(await frbc.locked(address)).to.equal(await frbc.atomic(locked[address]));
    }
  }

  if (!book[price]) {
    expect(await frbc.pointType(price)).to.equal(OrderType.Null);
    expect(await frbc.orderQuantity(price)).to.equal(0);
  } else {
    expect(await frbc.pointType(price)).to.equal(book[price].type);
    expect(await frbc.orderQuantity(price)).to.equal(book[price].orders.length);
    for (let i in book[price].orders) {
      expect(await frbc.orderTrader(price, i)).to.equal(book[price].orders[i].trader);
      expect(await frbc.orderAmount(price, i)).to.equal(book[price].orders[i].amount);
    }
  }
}

async function buy(trader, price, amount) {
  amount = ethers.BigNumber.from(amount);
  const { events, mutated } = await action(OrderType.Buy, trader.address, price, amount);
  await usd.transfer(frbc.address, amount.mul(price));
  const tx = await frbc.buy(trader.address, price, amount);
  await verify(price, tx, events, mutated);
}

function autoWithdraw(trader, events) {
  if (usdBalances[trader] && (!usdBalances[trader].isZero())) {
    events.push([[usd, "Transfer"], [frbc.address, trader, usdBalances[trader]]]);
    delete usdBalances[trader];
  }
  return events;
}

async function sell(trader, price, amount) {
  amount = ethers.BigNumber.from(amount);
  let { events, mutated } = await action(OrderType.Sell, trader.address, price, amount);
  events = autoWithdraw(trader.address, events);
  const tx = await frbc.connect(trader).sell(price, amount);
  await verify(price, tx, events, mutated);
}

async function cancel(trader, price) {
  let events = [];
  for (let i = (book[price].orders.length - 1); i !== -1; i--) {
    if (book[price].orders[i].trader === trader.address) {
      let { trader: address, amount } = book[price].orders[i];
      book[price].orders[i] = book[price].orders[book[price].orders.length - 1];
      book[price].orders.pop();

      if (book[price].type === OrderType.Buy) {
        usdBalances[address] = usdBalances[address] ? (
          usdBalances[address].add(amount.mul(price))
        ) : amount.mul(price);
      } else {
        locked[address] = locked[address].sub(amount);
      }
      events.push([[frbc, "OrderCancellation"], [address, price, amount]]);
    }
  }

  if (book[price].orders.length === 0) {
    delete book[price];
  }

  events = autoWithdraw(trader.address, events);

  const tx = await frbc.connect(trader).cancelOrder(price);
  await verify(price, tx, events, [trader.address]);
}

async function withdraw(trader) {
  let event = autoWithdraw(trader.address, [])[0];
  await expect(
    await frbc.withdrawTradeToken(trader.address)
  ).to.emit(...event[0]).withArgs(...event[1]);
}

describe("IntegratedLimitOrderDEX", accounts => {
  before(async () => {
    signers = await ethers.getSigners();
    ([ deployer, other ] = signers.splice(0, 2));

    usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");

    ({ frbc } = await FrabricERC20.deployFRBC(usd.address));
    expect(await frbc.tradeToken()).to.equal(usd.address);

    await frbc.mint(deployer.address, ethers.utils.parseUnits("777777"));
    frbcBalances[deployer.address] = ethers.BigNumber.from("777777");

    await frbc.setWhitelisted(other.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.mint(other.address, ethers.utils.parseUnits("333333"));
    frbcBalances[other.address] = ethers.BigNumber.from("333333");
  });

  it("should be able to convert values to atomic units properly", async () => {
    expect(await frbc.atomic(1)).to.equal(ethers.utils.parseUnits("1"));
  });

  it("shouldn't let you sell more than you have", async () => {
    let error = `NotEnoughFunds(${
      await frbc.atomic(frbcBalances[deployer.address].add(1))
    }, ${
      await frbc.atomic(frbcBalances[deployer.address])
    })`;
    await expect(
      frbc.sell(1, frbcBalances[deployer.address].add(1))
    ).to.be.revertedWith(error);
  });

  it("should be able to place sell orders", async () => {
    await sell(deployer, 100, 5);
  });

  it("should be able to place buy orders", async () => {
    await buy(deployer, 50, 2);
  });

  it("should be able to fill sell orders", async () => {
    await buy(other, 100, 5);
  });

  it("should be able to fill buy orders", async () => {
    await sell(other, 50, 2);
  });

  it("should be able to place multiple orders at the same price point", async () => {
    await sell(deployer, 100, 5);
    await sell(other, 100, 3);
    await sell(deployer, 100, 8);
  });

  it("should be able to cancel sell orders", async () => {
    await cancel(other, 100);
  });

  it("should be able to cancel multiple orders at the same price point", async () => {
    await cancel(deployer, 100);
  });

  it("should be able to cancel buy orders", async () => {
    await buy(deployer, 1, 1);
    await cancel(deployer, 1);
  });

  it("should be able to partially fill orders", async () => {
    await sell(deployer, 1, 5);
    await buy(other, 1, 3);
  });

  it("should be able to fill orders and place a new one", async () => {
    await buy(other, 1, 5);
  });

  it("should allow withdrawing", async () => {
    await withdraw(deployer);
  });

  // TODO: Trigger a removal from _fill where it's the only order at that price
  // TODO: Trigger a removal from cancelOrder where it's the only order at that price
  // TODO: Trigger a removal from _fill/cancelOrder in the middle of other orders
  // TODO: Verify orderAmount is 0 for orders of removed people

  it("should fuzz without issue", async () => {
    const prices = [...Array(FUZZ_ROUNDS / 50).keys()].map(x => x + 1);
    for (let i = 0; i < FUZZ_ROUNDS; i++) {
      let action = Math.floor(Math.random() * 3);
      let addr = Math.floor(Math.random() * 2);
      let price = prices[Math.floor(Math.random() * prices.length)];

      // Prevent cancelling on a non-existent price point
      if (!book[price]) {
        // Shows bias towards buy
        action = action % 2;
      }

      if (action == 0) {
        await buy([deployer, other][addr], price, Math.floor(Math.random() * 100) + 1);
      } else if (action == 1) {
        await sell([deployer, other][addr], price, Math.floor(Math.random() * 100) + 1);
      } else if (action == 2) {
        await cancel([deployer, other][addr], price);
      }
    }
  });
});
