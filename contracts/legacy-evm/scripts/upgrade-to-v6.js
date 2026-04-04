const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading BuxBoosterGame to V6 (Referral System) with account:", deployer.address);
  console.log("Proxy address:", PROXY_ADDRESS);

  // Step 1: Deploy new implementation
  console.log("\n=== Step 1: Deploy New Implementation ===");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const newImpl = await BuxBoosterGame.deploy({ gasLimit: 5000000 });
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("New V6 implementation deployed at:", newImplAddress);

  // Step 2: Upgrade proxy to new implementation
  console.log("\n=== Step 2: Upgrade Proxy ===");
  const proxy = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  try {
    const upgradeTx = await proxy.upgradeToAndCall(newImplAddress, "0x", { gasLimit: 5000000 });
    console.log("Upgrade transaction:", upgradeTx.hash);
    await upgradeTx.wait();
    console.log("Proxy upgraded to V6 implementation");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    process.exit(1);
  }

  // Step 3: Initialize V6 (sets buxReferralBasisPoints to 100 = 1%)
  console.log("\n=== Step 3: Initialize V6 ===");

  // Check current buxReferralBasisPoints value
  let currentBasisPoints;
  try {
    currentBasisPoints = await proxy.buxReferralBasisPoints();
    console.log("Current buxReferralBasisPoints:", currentBasisPoints.toString());
  } catch (e) {
    currentBasisPoints = 0n;
    console.log("buxReferralBasisPoints not yet initialized");
  }

  if (currentBasisPoints > 0n) {
    console.log("Referral basis points already initialized!");
  } else {
    console.log("Calling initializeV6...");
    try {
      const initTx = await proxy.initializeV6();
      console.log("Initialize transaction:", initTx.hash);
      await initTx.wait();

      const newBasisPoints = await proxy.buxReferralBasisPoints();
      console.log("buxReferralBasisPoints set to:", newBasisPoints.toString(), "(1%)");
    } catch (error) {
      console.error("Initialization failed:", error.message);
      if (error.data) {
        console.error("Error data:", error.data);
      }
      process.exit(1);
    }
  }

  // Step 4: Set Referral Admin
  console.log("\n=== Step 4: Set Referral Admin ===");
  const REFERRAL_ADMIN_BB = "0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad";

  const currentAdmin = await proxy.referralAdmin();
  console.log("Current referralAdmin:", currentAdmin);

  if (currentAdmin.toLowerCase() === REFERRAL_ADMIN_BB.toLowerCase()) {
    console.log("Referral admin already set!");
  } else {
    console.log("Setting referral admin to:", REFERRAL_ADMIN_BB);
    try {
      const adminTx = await proxy.setReferralAdmin(REFERRAL_ADMIN_BB);
      console.log("Set admin transaction:", adminTx.hash);
      await adminTx.wait();
      console.log("Referral admin set successfully");
    } catch (error) {
      console.error("Failed to set referral admin:", error.message);
      // Don't exit - this is not critical for the upgrade itself
    }
  }

  // Step 5: Verify configuration
  console.log("\n=== Verification ===");
  const basisPoints = await proxy.buxReferralBasisPoints();
  const finalAdmin = await proxy.referralAdmin();
  console.log("BuxBoosterGame.buxReferralBasisPoints:", basisPoints.toString());
  console.log("BuxBoosterGame.referralAdmin:", finalAdmin);

  if (basisPoints === 100n && finalAdmin.toLowerCase() === REFERRAL_ADMIN_BB.toLowerCase()) {
    console.log("\nBuxBoosterGame V6 upgrade complete!");
    console.log("\nReferral System Configuration:");
    console.log("- BUX referral reward: 1% of losing bets");
    console.log("- Referral admin:", REFERRAL_ADMIN_BB);
    console.log("\nNext steps:");
    console.log("1. Upgrade ROGUEBankroll to V8 with referral support");
    console.log("2. Set ROGUE referral basis points to 20 (0.2%)");
    console.log("3. Set ROGUEBankroll referral admin to 0x138742ae11E3848E9AF42aC0B81a6712B8c46c11");
    console.log("4. Deploy ReferralRewardPoller in Blockster backend");
    console.log("5. Update @deploy_block in ReferralRewardPoller");
  } else {
    console.log("\nConfiguration mismatch - please verify manually");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
