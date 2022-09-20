const { ethers } = require("hardhat");

const beaconproxyAddress = "";
const infura_key = "";
const network = 5;
const private_key_of_signer = "";
const participant_address = "";


const domain = {
    name: "Frabric Protocol",
    version: "1",
    chainId: 5,
    verifyingContract: beaconproxyAddress
}
const types = {
    Vouch: [
        {type: "address", name: "participant"}
    ]
}

function sign(signer, data) {
    return signer._signTypedData(domain, types, data)
}
const provider = new ethers.providers.InfuraProvider(network, infura_key)
const signer = new ethers.Wallet(private_key_of_signer , provider)

const signature = sign(signer, {participant: participant_address});
console.log(signature);
