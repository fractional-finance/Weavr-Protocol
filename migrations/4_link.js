/*
const ArbitrumBridgeWrapperL1 = artifacts.require("ArbitrumBridgeWrapperL1");
const ArbitrumBridgeWrapperL2 = artifacts.require("ArbitrumBridgeWrapperL2");
const FrabricL1 = artifacts.require("FrabricL1");
const FrabricL2 = artifacts.require("FrabricL2");
const FractionalNFTL1 = artifacts.require("FractionalNFTL1");
const FractionalNFTL2 = artifacts.require("FractionalNFTL2");

module.exports = async function (deployer, _, accounts) {
  let frabric1 = FrabricL1.deployed();
  let frabric2 = FrabricL2.deployed();
  let dao = DAO.deployed();
  frabric2.initialize(frabric1.address);
  frabric1.initialize(initialBridge, dao.address, frabric2.address);

  let nft1 = FractionalNFTL1.deployed();
  let nft2 = FractionalNFTL2.deployed();
  nft1.initialize(ArbitrumBridgeWrapperL1.deployed().address, dao.address, nft2.address);
  nft2.initialize(ArbitrumBridgeWrapperL2.deployed().address, nft1.address);
};
*/
