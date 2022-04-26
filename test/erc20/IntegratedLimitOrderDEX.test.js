const { ethers } = require("hardhat");
const { assert, expect } = require("chai");

const FrabricERC20 = require("../../scripts/deployFrabricERC20.js");

const { OrderType, impermanent: commonImpermanent } = require("../common.js");

// Do not set below 100
// While it's theoretically fine to only fuzz on a single price point, and the
// higher level of interactions would create more complex situations, multiple
// price points will exist in the real world. Therefore, they should here
const FUZZ_ROUNDS = 100;

let deployer, other, removed;
let book = {}, usdBalances = {}, frbcBalances = {}, locked = {};
let usd, frbc, parent;

// Recursive function to ensure members of an object are BigNumber
function recBN(obj) {
  if (typeof(obj) === "object") {
    for (let key in obj) {
      if (obj[key].type === "BigNumber") {
        obj[key] = ethers.BigNumber.from(obj[key].hex);
      } else {
        obj[key] = recBN(obj[key]);
      }
    }
  }
  return obj;
}

function clone(obj) {
  return recBN(JSON.parse(JSON.stringify(obj)));
}

function impermanent(test) {
  return commonImpermanent(async () => {
    let bookCopy = clone(book);
    let usdBalancesCopy = clone(usdBalances);
    let frbcBalancesCopy = clone(frbcBalances);
    let lockedCopy = clone(locked);
    await test();
    book = bookCopy;
    usdBalances = usdBalancesCopy;
    frbcBalances = frbcBalancesCopy;
    locked = lockedCopy;
  });
}

function sold(address, price, amount) {
  frbcBalances[address] = frbcBalances[address].sub(amount);
  locked[address] = locked[address].sub(amount);
  usdBalances[address] = usdBalances[address] ? (
    usdBalances[address].add(amount.mul(price))
  ) : amount.mul(price);
}

async function bought(address, from, price, amount) {
  frbcBalances[address] = frbcBalances[address] ? (
    frbcBalances[address].add(amount)
  ) : amount;
  return [[frbc, "Transfer"], [from, address, await frbc.atomic(amount)]];
}

async function action(type, trader, price, amount) {
  amount = ethers.BigNumber.from(amount);

  let counter, method;
  if (type === OrderType.Buy) {
    counter = OrderType.Sell;
  } else {
    counter = OrderType.Buy;
  }

  if (type === OrderType.Sell) {
    locked[trader] = locked[trader] ? locked[trader].add(amount) : amount;
  }

  // Simulate the trade with our variables to get the events which should be emitted
  let events = [];
  let mutated = [trader];
  if (book.hasOwnProperty(price)) {
    if (book[price].type === counter) {
      for (let i = (book[price].orders.length - 1); i !== -1; i--) {
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
        events.push([[frbc, "OrderFill"], [trader, order.trader, price, filled]]);
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
    events.push([[frbc, "Order"], [type, price]]);
    events.push([[frbc, "OrderIncrease"], [trader, price, amount]]);
  }

  return { events, mutated };
}

async function pointCheck(price, point) {
  if (!point) {
    point = { type: OrderType.Null, orders: [] };
  }

  expect(await frbc.pointType(price)).to.equal(point.type);
  expect(await frbc.orderQuantity(price)).to.equal(point.orders.length);
  for (let i in point.orders) {
    expect(await frbc.orderTrader(price, i)).to.equal(point.orders[i].trader);
    expect(await frbc.orderAmount(price, i)).to.equal(point.orders[i].amount);
  }
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

  await pointCheck(price, book[price]);
}

async function buyCore(trader, price, amount) {
  await usd.transfer(frbc.address, ethers.BigNumber.from(amount).mul(price));
  return frbc.buy(trader, price, amount);
}

async function buy(trader, price, amount) {
  arguments[0] = arguments[0].address;
  const { events, mutated } = await action(OrderType.Buy, ...arguments);
  const tx = await buyCore(...arguments);
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
    const signers = await ethers.getSigners();
    ([ deployer, other, removed ] = signers.splice(0, 3));

    usd = await (await ethers.getContractFactory("TestERC20")).deploy("Test USD", "TUSD");

    ({ frbc } = await FrabricERC20.deployFRBC(usd.address));
    expect(await frbc.tradeToken()).to.equal(usd.address);

    await frbc.mint(deployer.address, ethers.utils.parseUnits("777777"));
    frbcBalances[deployer.address] = ethers.BigNumber.from("777777");

    await frbc.setWhitelisted(other.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.mint(other.address, ethers.utils.parseUnits("333333"));
    frbcBalances[other.address] = ethers.BigNumber.from("333333");

    ({ frbc: parent } = await FrabricERC20.deployFRBC(usd.address));
    await frbc.setParent(parent.address);

    await parent.setWhitelisted(removed.address, "0x0000000000000000000000000000000000000000000000000000000000000001");
    await frbc.mint(removed.address, ethers.utils.parseUnits("1"));
    frbcBalances[removed.address] = ethers.BigNumber.from("1");
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

  it("shouldn't allow frozen accounts to place orders", impermanent(async () => {
    await frbc.freeze(removed.address, 9999999999);

    await expect(
      frbc.connect(removed).sell(5, 1)
    ).to.be.revertedWith(`Frozen("${removed.address}")`);

    await expect(
      buyCore(removed.address, 5, 1)
    ).to.be.revertedWith(`Frozen("${removed.address}")`);
  }));

  it("should let you fill orders of frozen accounts", impermanent(async () => {
    await sell(removed, 5, 1);
    await frbc.freeze(removed.address, 9999999999);
    await buy(deployer, 5, 1);
  }));

  async function fillRemoval(type) {
    let tx;
    // Place an order to trigger fill
    if (type === OrderType.Sell) {
      tx = await buyCore(deployer.address, 5, 1);
    } else {
      tx = await frbc.sell(5, 1);
    }
    type = OrderType.counter(type);

    // It should not fill this order
    await expect(tx).to.not.emit(frbc, "OrderFill");

    // It should place the order, fully on the other side without alterations
    await expect(tx).to.emit(frbc, "Order").withArgs(type, 5);
    await expect(tx).to.emit(frbc, "OrderIncrease").withArgs(deployer.address, 5, 1);
    await pointCheck(5, { type, orders: [{ trader: deployer.address, amount: 1 }] });

    return tx;
  }

  function cancelRemoval(swap) {
    return async (type) => {
      // While fill can solely pop, as it only ever works on the tail orders,
      // dropping any it fills, cancel does a full iteration and may cancel a middle
      // item
      if (swap) {
        // Add an additional order
        if (type === OrderType.Sell) {
          await frbc.connect(other).sell(5, 1);
        } else {
          await buyCore(other.address, 5, 1);
        }
      }

      const tx = await frbc.cancelOrder(5);
      if (!swap) {
        // It should clear the price point
        await pointCheck(5, null);
      } else {
        // It should swap the other order
        await pointCheck(5, { type, orders: [{ trader: other.address, amount: 1 }] });
      }

      return tx;
    }
  }

  function removalTest(i, test) {
    return impermanent(async () => {
      let type, amount;
      if (i !== 2) {
        type = OrderType.Sell;
        amount = 1;
        await sell(removed, 5, 1);
      } else {
        type = OrderType.Buy;
        amount = 3;
        await buy(removed, 5, 3);
      }

      let alreadyRemoved = i !== 1;
      if (alreadyRemoved) {
        // Already removed, so we're solely dropping the order
        await frbc.remove(removed.address, 0);
        assert(await frbc.removed(removed.address));
      } else {
        // Needs to be removed, so we're removing and dropping the orders
        await parent.remove(removed.address, 0);
        expect(await frbc.removed(removed.address)).to.equal(false);
      }

      // The order should still exist at this point yet the amount should return 0
      await pointCheck(5, { type, orders: [{ trader: removed.address, amount: 0 }] });

      const tx = await test(type);

      // It should trigger removal
      assert(await frbc.removed(removed.address));

      // The only transfer should be the removal's
      const transfers = (await tx.wait()).events.filter(e => e.event === "Transfer");
      if (alreadyRemoved) {
        expect(transfers.length).to.equal(0);
      } else {
        expect(transfers.length).to.equal(1);
        expect(transfers[0].args.to).to.equal(await frbc.auction());
      }

      if (type === OrderType.Buy) {
        // If this was the buy order variation, ensure the funds were returned
        expect(await frbc.tradeTokenBalances(removed.address)).to.equal(15);
        await expect(
          await frbc.withdrawTradeToken(removed.address)
        ).to.emit(usd, "Transfer").withArgs(frbc.address, removed.address, 15);
      }

      // It should have cancelled the order
      await expect(tx).to.emit(frbc, "OrderCancellation").withArgs(removed.address, 5, amount);

      // Their balance should be unaffected
      expect(await frbc.balanceOf(removed.address)).to.equal(0);
      expect(await frbc.locked(removed.address)).to.equal(0);
    });
  }

  for (let i = 0; i < 3; i++) {
    const context = ["(removed)", "(removing)", "(removed, dropping buy)"][i];
    it(`should call remove when filling orders ${context}`, removalTest(i, fillRemoval));
    it(`should call remove when cancelling orders without a swap remove ${context}`, removalTest(i, cancelRemoval(false)));
    it(`should call remove when cancelling orders with a swap remove ${context}`, removalTest(i, cancelRemoval(true)));
  }

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

      if (action === 0) {
        await buy([deployer, other][addr], price, Math.floor(Math.random() * 100) + 1);
      } else if (action === 1) {
        await sell([deployer, other][addr], price, Math.floor(Math.random() * 100) + 1);
      } else if (action === 2) {
        await cancel([deployer, other][addr], price);
      }
    }
  });
});
