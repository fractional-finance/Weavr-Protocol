const ArbitrumBridgeWrapper = artifacts.require("ArbitrumBridgeWrapperL1");
//const Frabric = artifacts.require("FrabricL1");
//const FractionalNFT = artifacts.require("FractionalNFTL1");

module.exports = function (deployer) {
  deployer.deploy(ArbitrumBridgeWrapper);
  //deployer.deploy(Frabric);
  //deployer.deploy(FractionalNFT);
};
