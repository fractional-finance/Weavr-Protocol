const { ethers } = require("hardhat");

const bond = "0x9ed8B34B459489bF3fD88675A14fBc0a9b1C9715";
const threadDeployer = "0xC1Bd090178F459b70b05b169422D05934Fea71AB";
const verifier = "0x4C3D84E96EB3c7dEB30e136f5150f0D4b58C7bdB";
const governor = "0x2C4fEAaab2F640738Dfd5535cb5AB91dE4e113bA";


const payload = (new ethers.utils.AbiCoder()).encode(
    ["address", "address", "address", "address"],
    [bond, threadDeployer, verifier, governor]
)

console.log(payload);