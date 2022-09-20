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
    KYCVerification: [
        { type: "uint8",   name: "participantType" },
        { type: "address", name: "participant" },
        { type: "bytes32", name: "kyc" },
        { type: "uint256", name: "nonce" }
    ]
}

function sign(signer, data) {
    return signer._signTypedData(domain, types, data)
}
const provider = new ethers.providers.InfuraProvider(network, infura_key)
const signer = new ethers.Wallet(private_key_of_signer , provider)

const signature = sign(signer, {
    participantType: 6,
    participant: participant_address,
    kyc: ethers.utils.id(participant_address),
    nonce: 0
});
console.log(signature);
