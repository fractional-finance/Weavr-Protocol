const { ethers } = require("hardhat");

module.exports = async () => {
  const signer = (await ethers.getSigners())[0];

  const Factory = await ethers.ContractFactory.fromSolidity(
    require("@uniswap/v2-core/build/UniswapV2Factory.json"),
    signer
  );
  // Use a fee setter address of 0
  const factory = await Factory.deploy(ethers.constants.AddressZero);

  const Router = await ethers.ContractFactory.fromSolidity(
    require("@uniswap/v2-periphery/build/UniswapV2Router02.json"),
    signer
  );
  // Use a WETH address of 0 as we never use ETH functionality
  const router = await Router.deploy(factory.address, ethers.constants.AddressZero);

  return { factory, router };
};

if (require.main === module) {
  module.exports()
    .then(contracts => {
      console.log("Uniswap v2 Factory: " + contracts.factory.address);
      console.log("Uniswap v2 Router:  " + contracts.router.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
