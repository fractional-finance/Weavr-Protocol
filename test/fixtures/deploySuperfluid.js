async function deploySuperfluid(web3, from, erc20Address) {
  // Deploy Superfluid
  const SuperfluidJSON = require("@superfluid-finance/ethereum-contracts/build/contracts/Superfluid.json");
  const Superfluid = new web3.eth.Contract(SuperfluidJSON.abi, null, {
    from,
    data: SuperfluidJSON.bytecode
  });
  let superfluid = await Superfluid.deploy({ arguments: [true, false] }).send();
  // Set ourselves as the governance contract so we can register an agreement
  await superfluid.methods.initialize(from).send();

  // Deploy IDA
  const IDAJSON = require("@superfluid-finance/ethereum-contracts/build/contracts/IInstantDistributionAgreementV1.json");
  const IDA = new web3.eth.Contract(IDAJSON.abi, null {
    from,
    data: IDA.bytecode
  });
  let ida = await IDA.deploy().send();
  await superfluid.registerAgreementClass(ida.options.address).send();

  // Deploy the SuperToken
  const SuperTokenJSON = require("@superfluid-finance/ethereum-contracts/build/contracts/SuperToken.json");
  const SuperToken = new web3.eth.Contract(SuperTokenJSON.abi, null, {
    from,
    data: SuperTokenJSON.bytecode
  });
  let token = await SuperToken.deploy({ arguments: [superfluid.options.address] }).send();
  await token.initialize(erc20Address, 2, "USD Test", "USD").send();

  return { superfluid, ida, token };
}
