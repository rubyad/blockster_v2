// Upgrade ROGUEBankroll to V9 - Per-difficulty stats tracking
// This upgrade adds:
// - buxBoosterBetsPerDifficulty mapping - bet counts per difficulty level
// - buxBoosterPnLPerDifficulty mapping - P/L per difficulty level
// - getBuxBoosterPlayerStats() view function for querying full stats

const { ethers, upgrades } = require("hardhat");

async function main() {
  const ROGUE_BANKROLL_PROXY = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  console.log("Upgrading ROGUEBankroll to V9...");
  console.log("Proxy address:", ROGUE_BANKROLL_PROXY);

  // Get the contract factory
  const ROGUEBankroll = await ethers.getContractFactory("ROGUEBankroll");

  // Upgrade the proxy
  console.log("\nUpgrading proxy...");
  const upgraded = await upgrades.upgradeProxy(ROGUE_BANKROLL_PROXY, ROGUEBankroll, {
    unsafeAllowRenames: true,
  });

  await upgraded.waitForDeployment();

  // Get the new implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(ROGUE_BANKROLL_PROXY);

  console.log("\n=== Upgrade Complete ===");
  console.log("Proxy address:", ROGUE_BANKROLL_PROXY);
  console.log("New implementation:", implAddress);

  // Verify the new function exists
  console.log("\nVerifying new function...");
  const contract = await ethers.getContractAt("ROGUEBankroll", ROGUE_BANKROLL_PROXY);

  // Test the new view function with a sample address
  const testAddress = "0x0000000000000000000000000000000000000001";
  try {
    const stats = await contract.getBuxBoosterPlayerStats(testAddress);
    console.log("getBuxBoosterPlayerStats() works!");
    console.log("  - Returns 8 values (6 uint256 + 2 arrays)");
    console.log("  - betsPerDifficulty array length:", stats.betsPerDifficulty.length);
    console.log("  - pnlPerDifficulty array length:", stats.pnlPerDifficulty.length);
  } catch (error) {
    console.error("Error calling getBuxBoosterPlayerStats:", error.message);
  }

  console.log("\n=== V9 Features ===");
  console.log("1. Per-difficulty bet tracking for ROGUE bets");
  console.log("2. Per-difficulty P/L tracking for ROGUE bets");
  console.log("3. getBuxBoosterPlayerStats(address) view function");
  console.log("\nNote: Historical bets won't have per-difficulty data.");
  console.log("Only new bets after this upgrade will be tracked.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
