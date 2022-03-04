const { task } = require('hardhat/config');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

// temporary until complete conversion
require("@nomiclabs/hardhat-truffle5");
// TBR to be reaearch on
require("@nomiclabs/hardhat-waffle");
// Solidy Coverage plugin
require("solidity-coverage");

// Basic task example
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  solidity: "0.8.4",
};
