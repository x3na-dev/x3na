import {
  loadFixture,
  setBalance,
  time,
  setNextBlockBaseFeePerGas,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers, upgrades } from "hardhat";
import { Referrals, X3NA } from "../typechain-types";
import type { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";

const ether = ethers.parseEther;

describe("x3na", function () {
  let user: HardhatEthersSigner;
  let admin: HardhatEthersSigner;
  let x3na: X3NA;
  let referrals: Referrals;

  beforeEach(async function () {
    ({ user, admin, x3na, referrals } = await loadFixture(deploy));
  });

  it("bet win manual claim", async function () {
    const round = 1;
    await x3na.connect(admin).startRound(round, 30, 30, "0x00");

    await x3na.connect(user).bet(round, 0, { value: ether("3000") });
    await x3na.connect(admin).bet(round, 1, { value: ether("7000") });

    await setBalance(user.address, 0); // reset balance
    await time.increase(31);
    await x3na.connect(admin).lockRound(round, 228);
    await time.increase(31);
    await x3na.connect(admin).endRound(round, 1337);

    expect(await ethers.provider.getBalance(user)).to.be.eq(ether("0")); // not claimed yet

    await setNextBlockBaseFeePerGas(0); // to conveniently watch native balance changes
    await x3na.connect(user).claim([round], { gasPrice: 0 });
    expect(await ethers.provider.getBalance(user)).to.be.eq(ether("9000")); // 10% fee
  });

  it("bet win autosend", async function () {
    const round = 1;
    await x3na.connect(admin).startRound(round, 30, 30, "0x00");

    await x3na.connect(user).bet(round, 0, { value: ether("3000") });
    await x3na.connect(admin).bet(round, 1, { value: ether("7000") });

    await setBalance(user.address, 0); // reset balance
    await time.increase(31);
    await x3na.connect(admin).lockRound(round, 228);
    await time.increase(31);
    await x3na.connect(admin).endRoundAndSendRewards(round, 1337, 0, 0);

    expect(await ethers.provider.getBalance(user)).to.be.eq(ether("8999.9997")); // 10% fee + 0.0003 for auto-send
  });
});

export async function deploy() {
  const [admin, user] = await ethers.getSigners();

  const referralsFactory = await ethers.getContractFactory("Referrals");
  const x3NAFactory = await ethers.getContractFactory("X3NA");

  const bufferSeconds = 30;
  const minBetAmount = ether("0.001");
  const maxBetAmount = ether("10000");
  const feeForAutoClaim = ether("0.0003");
  const treasuryFee = 10 * 100; // 10%
  const treasuryAddress = admin.address;
  const operatorAddress = admin.address;

  const referrals = await upgrades.deployProxy(referralsFactory, []);

  const x3na = await upgrades.deployProxy(x3NAFactory, [
    referrals.target,
    bufferSeconds,
    minBetAmount,
    maxBetAmount,
    feeForAutoClaim,
    treasuryFee,
    treasuryAddress,
    operatorAddress,
  ]);

  await referrals.grantRole(
    await referrals.OPERATOR_ROLE(),
    await x3na.getAddress()
  );

  return {
    admin,
    user,
    x3na,
    referrals,
  };
}
