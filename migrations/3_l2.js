const ArbitrumBridgeWrapper = artifacts.require("ArbitrumBridgeWrapperL2");
//const Frabric = artifacts.require("FrabricL2");
//const FractionalNFT = artifacts.require("FractionalNFTL2");

module.exports = async function (deployer) {
  let bridge = deployer.deploy(ArbitrumBridgeWrapper);
  /*
  let frabric = deployer.deploy(Frabric, bridge);
  let nft = deployer.deploy(FractionalNFT, bridge);

  let bonding = deployer.deploy(GovernorBond);
  let threadRef = deployer.deploy(Thread);
  let dao = deployer.deploy(DAO, bridge.address, frabric.address, nft.address, bonding.address, threadRef.address)
  */
};
