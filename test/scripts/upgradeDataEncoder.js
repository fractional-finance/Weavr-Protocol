const CONTRACTS = {
    BOND: process.env.BOND || "",
    THREAD_DEPLOYER: process.env.THREAD_DEPLOYER || ""
}

MEMBERS = {
    SIGNER: "0x4e022c910339f320f08817dc0596a92044913C02",
    GOVERNOR: "0x901268a9AEB7fcFaA5D667C52a9790AE6C64713e"
}

function upgradeData () {
    const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "address", "address"],
        [CONTRACTS.BOND, CONTRACTS.THREAD_DEPLOYER, MEMBERS.SIGNER, MEMBERS.GOVERNOR],
      );
    console.log("DATA:\n", data);
    return data;
}

upgradeData();