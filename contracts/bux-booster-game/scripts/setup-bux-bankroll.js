/**
 * Post-deploy setup for BUXBankroll:
 *   1. Set referral admin
 *   2. Set referral basis points (20 = 0.2%)
 *   3. Initial house deposit (owner approves BUX + deposits)
 *
 * Usage:
 *   BUX_BANKROLL_PROXY=0x... npx hardhat run scripts/setup-bux-bankroll.js --network rogueMainnet
 *   BUX_BANKROLL_PROXY=0x... DEPOSIT_AMOUNT=100000 npx hardhat run scripts/setup-bux-bankroll.js --network rogueMainnet
 *
 * Notes:
 *   - setPlinkoGame will be called later in Phase P3 when PlinkoGame is deployed
 *   - DEPOSIT_AMOUNT is in whole BUX (e.g. 100000 = 100,000 BUX). Omit to skip deposit.
 */

const { ethers } = require("hardhat");

const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const REFERRAL_ADMIN = "0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad";
const REFERRAL_BASIS_POINTS = 20; // 0.2%

async function main() {
  const proxyAddress = process.env.BUX_BANKROLL_PROXY;
  if (!proxyAddress) {
    console.error("ERROR: Set BUX_BANKROLL_PROXY env var to the deployed proxy address");
    process.exit(1);
  }

  const depositAmount = process.env.DEPOSIT_AMOUNT
    ? ethers.parseEther(process.env.DEPOSIT_AMOUNT)
    : null;

  const [deployer] = await ethers.getSigners();
  console.log("=== BUXBankroll Post-Deploy Setup ===");
  console.log("Proxy:", proxyAddress);
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  const bankroll = await ethers.getContractAt("BUXBankroll", proxyAddress);

  // Verify ownership
  const owner = await bankroll.owner();
  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error(`ERROR: Deployer ${deployer.address} is not owner ${owner}`);
    process.exit(1);
  }

  // --- Step 1: Set Referral Admin ---
  console.log("\n--- Step 1: Set Referral Admin ---");
  const currentAdmin = await bankroll.referralAdmin();
  if (currentAdmin.toLowerCase() === REFERRAL_ADMIN.toLowerCase()) {
    console.log("Referral admin already set to:", REFERRAL_ADMIN);
  } else {
    console.log("Setting referral admin to:", REFERRAL_ADMIN);
    const tx1 = await bankroll.setReferralAdmin(REFERRAL_ADMIN);
    console.log("Tx:", tx1.hash);
    await tx1.wait();
    console.log("Referral admin set successfully");
  }

  // --- Step 2: Set Referral Basis Points ---
  console.log("\n--- Step 2: Set Referral Basis Points ---");
  const currentBps = await bankroll.referralBasisPoints();
  if (currentBps === BigInt(REFERRAL_BASIS_POINTS)) {
    console.log("Referral basis points already set to:", REFERRAL_BASIS_POINTS);
  } else {
    console.log("Setting referral basis points to:", REFERRAL_BASIS_POINTS, "(0.2%)");
    const tx2 = await bankroll.setReferralBasisPoints(REFERRAL_BASIS_POINTS);
    console.log("Tx:", tx2.hash);
    await tx2.wait();
    console.log("Referral basis points set successfully");
  }

  // --- Step 3: Initial House Deposit ---
  if (depositAmount) {
    console.log("\n--- Step 3: Initial House Deposit ---");
    console.log("Deposit amount:", ethers.formatEther(depositAmount), "BUX");

    const buxContract = await ethers.getContractAt("IERC20", BUX_TOKEN);

    // Check deployer's BUX balance
    const buxBalance = await buxContract.balanceOf(deployer.address);
    console.log("Deployer BUX balance:", ethers.formatEther(buxBalance));

    if (buxBalance < depositAmount) {
      console.error("ERROR: Insufficient BUX balance. Need", ethers.formatEther(depositAmount),
        "but have", ethers.formatEther(buxBalance));
      process.exit(1);
    }

    // Approve BUXBankroll to spend BUX
    console.log("Approving BUXBankroll to spend BUX...");
    const txApprove = await buxContract.approve(proxyAddress, depositAmount);
    console.log("Approve tx:", txApprove.hash);
    await txApprove.wait();
    console.log("Approved");

    // Deposit BUX
    console.log("Depositing BUX...");
    const txDeposit = await bankroll.depositBUX(depositAmount);
    console.log("Deposit tx:", txDeposit.hash);
    await txDeposit.wait();
    console.log("Deposited successfully");

    // Verify deposit
    const lpBalance = await bankroll.balanceOf(deployer.address);
    console.log("Deployer LP-BUX balance:", ethers.formatEther(lpBalance));
  } else {
    console.log("\n--- Step 3: Initial House Deposit ---");
    console.log("Skipped (set DEPOSIT_AMOUNT env var to deposit, e.g. DEPOSIT_AMOUNT=100000)");
  }

  // --- Verification ---
  console.log("\n--- Final Verification ---");
  const finalAdmin = await bankroll.referralAdmin();
  const finalBps = await bankroll.referralBasisPoints();
  const [totalBalance, liability, unsettledBets, netBalance, poolTokenSupply, poolTokenPrice] =
    await bankroll.getHouseInfo();

  console.log("referralAdmin:", finalAdmin);
  console.log("referralBasisPoints:", finalBps.toString());
  console.log("totalBalance:", ethers.formatEther(totalBalance), "BUX");
  console.log("netBalance:", ethers.formatEther(netBalance), "BUX");
  console.log("poolTokenSupply:", ethers.formatEther(poolTokenSupply), "LP-BUX");
  console.log("poolTokenPrice:", poolTokenPrice.toString(), "(1e18 = 1:1)");

  console.log("\n========================================");
  console.log("=== BUXBankroll Setup Complete ===");
  console.log("========================================");
  console.log("Referral admin:", finalAdmin);
  console.log("Referral rate: 0.2% of losing bets");
  if (depositAmount) {
    console.log("House deposit:", ethers.formatEther(depositAmount), "BUX");
  }
  console.log("\nNEXT: Deploy PlinkoGame (Phase P2), then call:");
  console.log("  bankroll.setPlinkoGame(PLINKO_GAME_PROXY)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
