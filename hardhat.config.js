// require("dotenv").config();

require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");

module.exports = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  networks: {}
};

if (process.env.RINKEBY) {
  module.exports.networks.rinkeby = {
    url: process.env.RINKEBY,
    accounts: [
      process.env.PRIVATE_KEY
    ]
  };
}
