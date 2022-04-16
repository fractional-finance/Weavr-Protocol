const hre = require("hardhat");
const { ethers, waffle } = hre;

// Support overriding the Beacon. It's generally Beacon yet may be SingleBeacon
module.exports = async (args, codeFactory, Beacon) => {
  const code = await codeFactory.deploy();

  if (Beacon == null) {
    Beacon = await ethers.getContractFactory("Beacon");
  }
  const beacon = await Beacon.deploy(await code.contractName.call(), ...args);
  // Sanity check ethers.utils.id usage while here
  // Ensures whitelist consistency for JS whitelisted participants/contracts and Solidity whitelisted contracts
  if ((await beacon.contractName.call()) != ethers.utils.id("Beacon")) {
    throw "ethers.utils.id doesn't line up with Solidity's keccak256";
  }

  // Any other release channels will default to this one for now
  await beacon.upgrade("0x0000000000000000000000000000000000000000", code.address);

  // Wait for two additional confirms due to issues otherwise
  // Only do this on actual networks (not the hardhat network)
  if ((await waffle.provider.getNetwork()).chainId != 31337) {
    let block = await waffle.provider.getBlockNumber();
    while ((block + 2) > (await waffle.provider.getBlockNumber())) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
  return beacon;
};
