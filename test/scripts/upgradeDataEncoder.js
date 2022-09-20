const { ethers } = require("hardhat");
const { ERRORS } = require("hardhat/internal/core/errors-list");

const CONTRACTS = {
    BOND: process.env.BOND || "CUSTOM_CONTRACT_ADDRESS",
    THREAD_DEPLOYER: process.env.THREAD_DEPLOYER || "CUSTOM_CONTRACT_ADDRESS"
}

MEMBERS = {
    SIGNER: "0x4e022c910339f320f08817dc0596a92044",
    GOVERNOR: "0x901268a9AEB7fcFaA5D667C52a9790AE6C64713e"
}

function upgradeData () {
    if(
        ethers.utils.isAddress(CONTRACTS.BOND) &&
        ethers.utils.isAddress(CONTRACTS.THREAD_DEPLOYER) &&
        ethers.utils.isAddress(MEMBERS.GOVERNOR) &&
        ethers.utils.isAddress(MEMBERS.SIGNER)
    ) {
        const data = ethers.utils.defaultAbiCoder.encode(
            ["address", "address", "address", "address"],
            [CONTRACTS.BOND, CONTRACTS.THREAD_DEPLOYER, MEMBERS.SIGNER, MEMBERS.GOVERNOR],
          );
        console.log("DATA:\n", data);
        return data;
    }
    throw new Error("SOME ADDRESS IS NOT PROPERLY SETUP")
}

upgradeData();