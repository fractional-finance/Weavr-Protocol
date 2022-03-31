const hre = require("hardhat");
const { ethers } = hre;

module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  return await (await ethers.getContractFactory("DEXRouter")).deploy();
};

if (require.main === module) {
  module.exports()
    .then(router => console.log("DEX Router: " + router.address))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
