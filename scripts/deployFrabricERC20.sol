const hre = require("hardhat");
const { ethers, upgrades } = hre;

module.exports = {
  deployFrabricERC20Beacon: async () => {
    // Run compile if it hasn't been run already
    // Prevents a print statement of "Nothing to compile" from repeatedly appearing
    process.hhCompiled ? await hre.run("compile") : null;
    process.hhCompiled = true;

    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");
    const code = await FrabricERC20.deploy();
    await code.deployed();

    const Beacon = await ethers.getContractFactory("Beacon");
    // Two release channels, A and B
    const beacon = await Beacon.deploy([2]);
    await beacon.deployed();
    // Set the release channel to the code
    // The second release channel will default to this release channel until distinctly set
    await beacon.upgrade("0x0000000000000000000000000000000000000000", code.address);
    return beacon;
  },

  deployFrabricERC20: async (beacon, name, symbol, supply, mintable, whitelist, dexToken) => {
    process.hhCompiled ? await hre.run("compile") : null;
    process.hhCompiled = true;

    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");

    if (!process.env.USDC) {
      process.env.USDC = "0x0000000000000000000000000000000000000000";
    }
    const frbc = await upgrades.deployBeaconProxy(
      beacon,
      FrabricERC20,
      [name, symbol, supply, mintable, whitelist, dexToken]
    );
    await frbc.deployed();
    return frbc;
  },

  deployFRBC: async (usdc) => {
    let result = { beacon: await module.exports.deployFrabricERC20Beacon() };
    result.frbc = await module.exports.deployFrabricERC20(
      result.beacon,
      "Frabric Token",
      "FRBC",
      0,
      true,
      "0x0000000000000000000000000000000000000000",
      usdc
    );
    return result;
  }
};

if (require.main === module) {
  if (!process.env.USDC) {
    process.env.USDC = "0x0000000000000000000000000000000000000000";
  }
  module.exports.deployFRBC(process.env.USDC)
    .then(contracts => {
      console.log("FrabricERC20 Beacon: " + contracts.beacon.address);
      console.log("FRBC: " + contracts.frbc.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
