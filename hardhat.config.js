require("dotenv").config();

require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");


module.exports = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 90
      }
    }
  },

  networks: {}
};

if (process.env.TENDERLY){
  const tdly = require("@tenderly/hardhat-tenderly");
  tdly.setup();
}


ACCOUNTS = []
WALLETS = []
process.env.PRIVATE_KEY ? ACCOUNTS.push(process.env.PRIVATE_KEY) : console.log("Deployer is not set!")
process.env.GOVERNOR ? ACCOUNTS.push(process.env.GOVERNOR) : console.log("Governor is not set!")


if(process.env.WALLETS) {
  WALLETS = (process.env.WALLETS).split(",");
  ACCOUNTS.concat(WALLETS)
}else {
  console.log("Voting wallets are not set.");
}


if (process.env.GOERLI) {
  module.exports.networks.goerli = {
    url: process.env.GOERLI,
    accounts: ACCOUNTS
  };
}

