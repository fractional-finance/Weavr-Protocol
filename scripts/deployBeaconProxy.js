const { upgrades } = require("hardhat");

// Support overriding the Beacon. It's generally Beacon yet may be SingleBeacon
module.exports = async (beaconAddress, contractFactory, args, opts) => {
    let beaconProxy;
    if (process.env.TENDERLY){
        contractFactory = contractFactory.nativeContractFactory;
    }
    if (opts == null) {
        beaconProxy = await upgrades.deployBeaconProxy(beaconAddress, contractFactory, args);
    } else {
        beaconProxy = await upgrades.deployBeaconProxy(beaconAddress, contractFactory, args, opts);
    }
    return beaconProxy;
};