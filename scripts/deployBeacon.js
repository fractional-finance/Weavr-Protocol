const { ethers, waffle } = require("hardhat");

// Support overriding the Beacon. It's generally Beacon yet may be SingleBeacon
module.exports = async (releaseChannels, codeFactory) => {
  const code = await codeFactory.deploy();
  let Beacon = await ethers.getContractFactory("Beacon");
  if (releaseChannels === "single") {
    Beacon = await ethers.getContractFactory("SingleBeacon");
    releaseChannels = null;
  }
  await code.deployed();
  let code_name = await code.functions.contractName();
  const beacon = await Beacon.deploy(code_name[0], releaseChannels);
  await beacon.deployed();
  let beacon_name = await beacon.functions.contractName();
  // Sanity check ethers.utils.id usage while here
  // Ensures whitelist consistency for JS whitelisted participants/contracts and Solidity whitelisted contracts
  if (beacon_name[0] !== ethers.utils.id("Beacon")) {
    throw "ethers.utils.id doesn't line up with Solidity's keccak256";
  }

  await (await beacon.upgrade(ethers.constants.AddressZero, 1, code.address, "0x")).wait();

  return beacon;
};
