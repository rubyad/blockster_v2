const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading BuxBoosterGame to V7 (Separated BUX Stats) with account:", deployer.address);
  console.log("Proxy address:", PROXY_ADDRESS);

  // Step 1: Deploy new implementation
  console.log("\n=== Step 1: Deploy New Implementation ===");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const newImpl = await BuxBoosterGame.deploy({ gasLimit: 5000000 });
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("New V7 implementation deployed at:", newImplAddress);

  // Step 2: Upgrade proxy to new implementation
  console.log("\n=== Step 2: Upgrade Proxy ===");
  const proxy = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  try {
    const upgradeTx = await proxy.upgradeToAndCall(newImplAddress, "0x", { gasLimit: 5000000 });
    console.log("Upgrade transaction:", upgradeTx.hash);
    await upgradeTx.wait();
    console.log("Proxy upgraded to V7 implementation");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    process.exit(1);
  }

  // Step 3: Initialize V7
  console.log("\n=== Step 3: Initialize V7 ===");

  console.log("Calling initializeV7...");
  try {
    const initTx = await proxy.initializeV7();
    console.log("Initialize transaction:", initTx.hash);
    await initTx.wait();
    console.log("V7 initialized successfully");
  } catch (error) {
    // Check if already initialized
    if (error.message.includes("InvalidInitialization")) {
      console.log("V7 already initialized (this is fine if upgrading from existing V7)");
    } else {
      console.error("Initialization failed:", error.message);
      if (error.data) {
        console.error("Error data:", error.data);
      }
      process.exit(1);
    }
  }

  // Step 4: Verify new functions are available
  console.log("\n=== Verification ===");

  try {
    // Test getBuxAccounting()
    const buxAccounting = await proxy.getBuxAccounting();
    console.log("\nBUX Global Accounting (starting values):");
    console.log("- Total Bets:", buxAccounting[0].toString());
    console.log("- Total Wins:", buxAccounting[1].toString());
    console.log("- Total Losses:", buxAccounting[2].toString());
    console.log("- Total Volume Wagered:", buxAccounting[3].toString());
    console.log("- Total Payouts:", buxAccounting[4].toString());
    console.log("- Total House Profit:", buxAccounting[5].toString());
    console.log("- Largest Win:", buxAccounting[6].toString());
    console.log("- Largest Bet:", buxAccounting[7].toString());

    // Test getBuxPlayerStats() with deployer address
    const playerStats = await proxy.getBuxPlayerStats(deployer.address);
    console.log("\nBUX Player Stats for", deployer.address + ":");
    console.log("- Total Bets:", playerStats[0].toString());
    console.log("- Wins:", playerStats[1].toString());
    console.log("- Losses:", playerStats[2].toString());
    console.log("- Total Wagered:", playerStats[3].toString());

    console.log("\n✅ BuxBoosterGame V7 upgrade complete!");
    console.log("\nNew Features:");
    console.log("- getBuxPlayerStats(address) - BUX-only player stats");
    console.log("- getBuxAccounting() - BUX global accounting");
    console.log("- buxPlayerStats mapping - BUX-only player data");
    console.log("- buxAccounting struct - BUX global data");
    console.log("\nNote: Stats start at 0 after upgrade. New BUX bets will populate these stats.");
    console.log("Old playerStats mapping preserved for historical reference but no longer written to.");

  } catch (error) {
    console.error("Verification failed:", error.message);
    console.log("\nPlease manually verify the upgrade by calling getBuxAccounting() on the contract");
  }

  console.log("\n=== Update CLAUDE.md ===");
  console.log("New V7 Implementation Address:", newImplAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
