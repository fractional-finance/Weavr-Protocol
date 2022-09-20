const { ethers, upgrades } = require("hardhat");
const { assert, expect, util } = require("chai");

const utils = {
    randomWallet: () => {
        const WALLET = ethers.Wallet.createRandom();
        console.log({
            id: WALLET.address,
            publicKey: WALLET.publicKey,
            privateKey: WALLET.privateKey,
            mnemonic: WALLET.mnemonic
        });
    },
    walletAddress: (privateKey) => {
        const wallet = new ethers.Wallet(privateKey)
        console.log(wallet.address);
        return wallet.address
    }
}

module.exports = async () => {

   utils.walletAddress(process.env.GOVERNOR);
    
}

const callModule = async () => {
    console.log("YESS");
    await module.exports()
}

if (require.main === module) {
    callModule()
}
