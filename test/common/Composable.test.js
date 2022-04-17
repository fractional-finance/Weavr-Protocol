const hre = require("hardhat");
const { ethers } = hre;

const { assert, expect } = require("chai");

let TestComposable, composable;

describe("Composable", () => {
  before(async () => {
    TestComposable = await ethers.getContractFactory("TestComposable");
    // Code
    composable = await TestComposable.deploy(true, false);
  });

  it("should have the correct name", async () => {
    expect(await composable.contractName()).to.equal(ethers.utils.id("TestComposable"));
  });

  it("should have the right version", async () => {
    expect(await composable.version()).to.equal(0);
    // Not code, finalized
    expect(await (await TestComposable.deploy(false, true)).version()).to.equal(ethers.constants.MaxUint256);
    // Not code, not finalized
    expect(await (await TestComposable.deploy(false, false)).version()).to.equal(1);
  });

  it("should be EIP-165 compliant", async () => {
    assert(!(await composable.supportsInterface("0x00000000")));
    assert(!(await composable.supportsInterface("0xFFFFFFFF")));
    assert(await composable.supportsInterface(TestComposable.interface.getSighash("supportsInterface")));
  });

  // Generally not tested due to the lack of easy EIP-165 interface ID generation
  // This is sufficiently short and the base of all EIP-165 support though
  it("should support its own interface", async () => {
    assert(await composable.supportsInterface(
      ethers.BigNumber.from(TestComposable.interface.getSighash("contractName"))
        .xor(TestComposable.interface.getSighash("version"))
        ._hex
    ));
  });
});
