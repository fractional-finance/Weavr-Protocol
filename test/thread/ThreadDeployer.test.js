describe("ThreadDeployer", () => {
  before(async () => {

  });

  it("should have tests", async () => {
    throw "Untested";
  });

  /*
  // Tested here as these irremovable contracts are actually init args
  it("should't deploy a Thread which lets you remove the Frabric/Timelock/Crowdfund", async () => {
    for (let irremovable of [frabric, timelock, crowdfund]) {
      await expect(
        thread.proposeParticipantRemoval(irremovable.address, 0, [], ethers.utils.id("Proposing removing irremovable participant"))
      ).to.be.revertedWith(`Irremovable("${irremovable.address}")`);
    }
  });
  */
});
