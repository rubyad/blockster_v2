const { ethers } = require("hardhat");

async function main() {
  const ROGUE_BANKROLL_PROXY = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
  const REFERRAL_ADMIN_RB = "0x138742ae11E3848E9AF42aC0B81a6712B8c46c11";
  const REFERRAL_BASIS_POINTS = 20; // 0.2%

  const [deployer] = await ethers.getSigners();
  console.log("Configuring ROGUEBankroll referral system with account:", deployer.address);
  console.log("ROGUEBankroll proxy:", ROGUE_BANKROLL_PROXY);

  // Get contract instance
  const rogueBankroll = await ethers.getContractAt("ROGUEBankroll", ROGUE_BANKROLL_PROXY);

  // Step 1: Set referral basis points
  console.log("\n=== Step 1: Set Referral Basis Points ===");
  try {
    const currentBasisPoints = await rogueBankroll.referralBasisPoints();
    console.log("Current referralBasisPoints:", currentBasisPoints.toString());

    if (currentBasisPoints === BigInt(REFERRAL_BASIS_POINTS)) {
      console.log("Referral basis points already set!");
    } else {
      console.log("Setting referralBasisPoints to:", REFERRAL_BASIS_POINTS, "(0.2%)");
      const tx1 = await rogueBankroll.setReferralBasisPoints(REFERRAL_BASIS_POINTS);
      console.log("Transaction:", tx1.hash);
      await tx1.wait();
      console.log("Referral basis points set successfully");
    }
  } catch (error) {
    console.error("Failed to set referral basis points:", error.message);
    process.exit(1);
  }

  // Step 2: Set referral admin
  console.log("\n=== Step 2: Set Referral Admin ===");
  try {
    const currentAdmin = await rogueBankroll.referralAdmin();
    console.log("Current referralAdmin:", currentAdmin);

    if (currentAdmin.toLowerCase() === REFERRAL_ADMIN_RB.toLowerCase()) {
      console.log("Referral admin already set!");
    } else {
      console.log("Setting referralAdmin to:", REFERRAL_ADMIN_RB);
      const tx2 = await rogueBankroll.setReferralAdmin(REFERRAL_ADMIN_RB);
      console.log("Transaction:", tx2.hash);
      await tx2.wait();
      console.log("Referral admin set successfully");
    }
  } catch (error) {
    console.error("Failed to set referral admin:", error.message);
    process.exit(1);
  }

  // Step 3: Verify configuration
  console.log("\n=== Verification ===");
  const finalBasisPoints = await rogueBankroll.referralBasisPoints();
  const finalAdmin = await rogueBankroll.referralAdmin();
  console.log("ROGUEBankroll.referralBasisPoints:", finalBasisPoints.toString());
  console.log("ROGUEBankroll.referralAdmin:", finalAdmin);

  if (finalBasisPoints === BigInt(REFERRAL_BASIS_POINTS) &&
      finalAdmin.toLowerCase() === REFERRAL_ADMIN_RB.toLowerCase()) {
    console.log("\nROGUEBankroll referral configuration complete!");
    console.log("\nConfiguration:");
    console.log("- ROGUE referral reward: 0.2% of losing bets");
    console.log("- Referral admin:", REFERRAL_ADMIN_RB);
  } else {
    console.log("\nConfiguration mismatch - please verify manually");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
