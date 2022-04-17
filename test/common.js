const { waffle } = require("hardhat");

module.exports = {
  snapshot: () => waffle.provider.send("evm_snapshot", []),
  revert: (id) => waffle.provider.send("evm_revert", [id])
}
