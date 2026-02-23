import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  const bufferSeconds = 30;
  const minBetAmount = ethers.parseEther("0.001");
  const maxBetAmount = ethers.parseEther("10000");
  const feeForAutoClaim = ethers.parseEther("0.0003");
  const treasuryFee = 5 * 100;
  const treasuryAddress = deployer.address;
  const operatorAddress = deployer.address;


  const referralsFactory = await ethers.getContractFactory("Referrals");
  const referralsContract = await upgrades.deployProxy(referralsFactory, []);
  await referralsContract.waitForDeployment();
  console.log("referralsContract deployed to:", await referralsContract.getAddress());

  const x3NAFactory = await ethers.getContractFactory("X3NA");
  const x3naContract = await upgrades.deployProxy(x3NAFactory, [
    await referralsContract.getAddress(),
    bufferSeconds,
    minBetAmount,
    maxBetAmount,
    feeForAutoClaim,
    treasuryFee,
    treasuryAddress,
    operatorAddress,
  ]);

  await x3naContract.waitForDeployment();
  console.log("x3naContract deployed to:", await x3naContract.getAddress());


  console.log("Setting OPERATOR_ROLE for x3naContract in referralsContract");
  await referralsContract.grantRole(
    await referralsContract.OPERATOR_ROLE(),
    await x3naContract.getAddress()
  );
  console.log("OPERATOR_ROLE granted");


}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
