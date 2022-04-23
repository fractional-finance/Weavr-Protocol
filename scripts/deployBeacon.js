const { ethers, waffle } = require("hardhat");

// Support overriding the Beacon. It's generally Beacon yet may be SingleBeacon
module.exports = async (releaseChannels, codeFactory) => {
  const code = await codeFactory.deploy();

  let Beacon = await ethers.getContractFactory("Beacon");
  if (releaseChannels === "single") {
    Beacon = await ethers.getContractFactory("SingleBeacon");
    releaseChannels = null;
  }
  const beacon = await Beacon.deploy(await code.contractName.call(), releaseChannels);
  // Sanity check ethers.utils.id usage while here
  // Ensures whitelist consistency for JS whitelisted participants/contracts and Solidity whitelisted contracts
  if ((await beacon.contractName.call()) != ethers.utils.id("Beacon")) {
    throw "ethers.utils.id doesn't line up with Solidity's keccak256";
  }

  // Any other release channels will default to this one for now
  await beacon.upgrade(ethers.constants.AddressZero, 1, code.address, "0x");

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
