const { ethers } = require("hardhat");

const provider = ethers.providers.getDefaultProvider("https://arbitrum-mainnet.infura.io/v3/10f965a85be14e40b1b7bb000a7be036");
const signer = new ethers.Wallet("PRIVATE_KEY", provider);
let participant = "0xe4e1aEF9c352a6A56e39f502612cA88a3441CFA5";


let signGlobal = [
    {
        name: "Weavr Protocol",
        version: "1",
        chainId: 421613,
        verifyingContract: "0xE7Dfe33e5191bde13E2ef5F00c6FeAA3C35676B1"
    },
    {
        Vouch: [
            { type: "address", name: "participant" }
        ],
        KYCVerification: [
            { type: "uint8",   name: "participantType" },
            { type: "address", name: "participant" },
            { type: "bytes32", name: "kyc" },
            { type: "uint256", name: "nonce" }
        ]
    }
];

function sign(signer, data) {
    let signArgs = JSON.parse(JSON.stringify(signGlobal));
    if (Object.keys(data).length === 1) {
        signArgs[1] = { Vouch: signArgs[1].Vouch };
    } else {
        signArgs[1] = { KYCVerification: signArgs[1].KYCVerification };
    }

    // Shim for the fact ethers.js will change this functions names in the future
    if (signer.signTypedData) {
        return signer.signTypedData(...signArgs, data);
    } else {
        return signer._signTypedData(...signArgs, data);
    }
}


let l = sign(
    signer,
    {
        participant: participant
    }
)
l.then(console.log);