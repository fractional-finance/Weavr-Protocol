const hre = require("hardhat");
const { ethers } = hre;

// Support overriding the Beacon. It's generally Beacon yet sometimes SingleBeacon
module.exports = async (args, codeFactory, Beacon) => {
  // Run compile if it hasn't been run already
  // Prevents a print statement of "Nothing to compile" from repeatedly appearing
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const code = await codeFactory.deploy();
  await code.deployed();

  if (Beacon == null) {
    Beacon = await ethers.getContractFactory("Beacon");
  }
  const beacon = await Beacon.deploy(args);
  await beacon.deployed();

  // Any other release channels will default to this one for now
  await beacon.upgrade("0x0000000000000000000000000000000000000000", code.address);
  return beacon;
};
