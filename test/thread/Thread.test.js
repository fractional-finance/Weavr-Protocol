const { ethers } = require("hardhat");
const { expect } = require("chai");

const Thread = require("../../scripts/deployThread.js");

let signers, governor, thread;

describe("Thread", async () => {
  before(async () => {
    signers = await ethers.getSigners();
    let owner = signers.splice(0, 1)[0];
    governor = signers.splice(0, 1)[0];
    thread = await Thread.deployTestThread(governor.address);
  });

  it("should have tests", async () => {
    throw "Untested";
  });
});
