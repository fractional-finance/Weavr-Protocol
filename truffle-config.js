module.exports = {
  networks: {
  },

  mocha: {
  },

  compilers: {
    solc: {
      version: "0.8.11",
      settings: {
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
