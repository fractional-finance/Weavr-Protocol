module.exports = {
  networks: {
  },

  mocha: {
  },

  compilers: {
    solc: {
      version: "0.8.11",
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 200
        },

        debug: {
          revertStrings: "strip"
        }
      }
    }
  }
};
