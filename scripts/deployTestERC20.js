const hre = require("hardhat");
const { ethers } = hre;

// Solely used for testing
module.exports = async () => {
  process.hhCompiled ? null : await hre.run("compile");
  process.hhCompiled = true;

  const TestERC20 = await ethers.getContractFactory("TestERC20");
  return await TestERC20.deploy("Test Token", "TERC");
};

if (require.main === module) {
  module.exports()
    .then(token => console.log("Test Token: " + token.address))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
