const hre = require("hardhat");
const { ethers } = hre;

// Support overriding the Beacon. It's generally Beacon yet may be SingleBeacon
module.exports = async (args, codeFactory, Beacon) => {
  const code = await codeFactory.deploy();

  if (Beacon == null) {
    Beacon = await ethers.getContractFactory("Beacon");
  }
  const beacon = await Beacon.deploy(...args, await code.contractName.call());

  // Any other release channels will default to this one for now
  await beacon.upgrade("0x0000000000000000000000000000000000000000", code.address);
  return beacon;
};
