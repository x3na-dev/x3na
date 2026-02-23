import { ethers, upgrades } from "hardhat";

async function main() {
  const referralsProxy = "0xff8dDbC654056CbCc2C8C96A24EC3D859473b6bc";
  const x3naProxy = "0x2BfF6c20964aa5cE17A998F903B6eA23A51F9543";

  const Referrals = await ethers.getContractFactory("Referrals");
  const X3NA = await ethers.getContractFactory("X3NA");

  console.log("Upgrading Referrals...");
  await upgrades.upgradeProxy(referralsProxy, Referrals);
  console.log("Referrals upgraded");

  console.log("Upgrading X3NA...");
  await upgrades.upgradeProxy(x3naProxy, X3NA);
  console.log("X3NA upgraded");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
