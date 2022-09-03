require("dotenv").config();

require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");
const tdly = require("@tenderly/hardhat-tenderly");
tdly.setup();

deployer = process.env.PRIVATE_KEY
voters = (process.env.WALLETS).split(',')
let accounts = []
accounts.push(deployer)

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
  networks: {
    arbitrum: {
      url: process.env.ARB_NITRO_TESTNET,
      accounts: [accounts.toString()],
      chainId: 421613
    }
  },
  defaultNetwork: "arbitrum",

};

if (process.env.RINKEBY) {
  module.exports.networks.rinkeby = {
    url: process.env.RINKEBY,
    accounts: accounts
  };
}
// if (process.env.ARB_NITRO_TESTNET) {
//   module.exports.networks.nitro_test = {
//     url: process.env.ARB_NITRO_TESTNET,
//     accounts: [
//       process.env.PRIVATE_KEY
//     ]
//   };
// }

if(process.env.GOERLI) {
  module.exports.networks.goerli = {
    url: process.env.GOERLI,
    accounts: [
      process.env.PRIVATE_KEY
    ]
  }
}

