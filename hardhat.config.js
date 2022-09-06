require("dotenv").config();

require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");
const tdly = require("@tenderly/hardhat-tenderly");
tdly.setup();


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

if (process.env.GOERLI) {
  module.exports.networks.goerli = {
    url: process.env.GOERLI,
    accounts: [
      process.env.PRIVATE_KEY
    ]
  };
}

