const { ethers } = require("hardhat");

const beaconproxyAddress = "";
infura_key = "10f965a85be14e40b1b7bb000a7be036";
network = 5;
private_key_of_signer = "";
const participant_address = "0x6bE56DbAA46dD1Ea477c1Cf19B511CB5bd342043";


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
