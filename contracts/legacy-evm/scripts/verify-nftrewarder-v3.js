const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * Verify NFTRewarder V3 on Roguescan
 *
 * This script:
 * 1. Outputs all the information needed for manual verification on Roguescan
 * 2. Verifies the V3 upgrade was successful by checking state
 *
 * Usage:
 *   npx hardhat run scripts/verify-nftrewarder-v3.js --network rogueMainnet
 */
async function main() {
  const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  console.log("=".repeat(60));
  console.log("NFTRewarder V3 Verification");
  console.log("=".repeat(60));
  console.log("");

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", PROXY_ADDRESS);

  // === On-Chain State Verification ===
  console.log("=== ON-CHAIN STATE VERIFICATION ===");
  console.log("");

  // Basic info
  const owner = await NFTRewarder.owner();
  const admin = await NFTRewarder.admin();
  const rogueBankroll = await NFTRewarder.rogueBankroll();

  console.log("Proxy Address:", PROXY_ADDRESS);
  console.log("Owner:", owner);
  console.log("Admin:", admin);
  console.log("ROGUEBankroll:", rogueBankroll);
  console.log("");

  // V3 Time Reward Features
  console.log("=== V3 TIME REWARD FEATURES ===");
  console.log("");

  // Time reward rates
  console.log("Time Reward Rates per Second (scaled by 1e18):");
  const hostessNames = ["Penelope", "Mia", "Cleo", "Sophia", "Luna", "Aurora", "Scarlett", "Vivienne"];
  const expectedRates = [
    2125029000000000000n,  // Penelope
    1912007000000000000n,  // Mia
    1700492000000000000n,  // Cleo
    1487470000000000000n,  // Sophia
    1274962000000000000n,  // Luna
    1062454000000000000n,  // Aurora
    849946000000000000n,   // Scarlett
    637438000000000000n    // Vivienne
  ];

  let allRatesCorrect = true;
  for (let i = 0; i < 8; i++) {
    const rate = await NFTRewarder.timeRewardRatesPerSecond(i);
    const expected = expectedRates[i];
    const status = rate === expected ? "✅" : "❌";
    if (rate !== expected) allRatesCorrect = false;
    console.log(`  ${status} ${hostessNames[i]}: ${rate.toString()} (expected ${expected.toString()})`);
  }
  console.log("");

  // Special NFT range
  const startId = await NFTRewarder.SPECIAL_NFT_START_ID();
  const endId = await NFTRewarder.SPECIAL_NFT_END_ID();
  console.log("Special NFT Range:");
  console.log(`  Start ID: ${startId.toString()} (expected 2340)`);
  console.log(`  End ID: ${endId.toString()} (expected 2700)`);
  console.log("");

  // Time reward pool
  const poolRemaining = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Time Reward Pool:");
  console.log(`  Remaining: ${ethers.formatEther(poolRemaining)} ROGUE`);
  console.log("");

  // === Roguescan Verification Info ===
  console.log("=".repeat(60));
  console.log("ROGUESCAN MANUAL VERIFICATION INFO");
  console.log("=".repeat(60));
  console.log("");
  console.log("To verify the implementation contract on Roguescan:");
  console.log("");
  console.log("1. Go to: https://roguescan.io/address/<IMPLEMENTATION_ADDRESS>/contract");
  console.log("   (Get implementation address from the upgrade tx logs or read proxy storage)");
  console.log("");
  console.log("2. Select: 'Verify & Publish'");
  console.log("");
  console.log("3. Enter the following:");
  console.log("   - Contract Address: <IMPLEMENTATION_ADDRESS>");
  console.log("   - Compiler Type: Solidity (Standard-Json-Input)");
  console.log("   - Compiler Version: v0.8.20");
  console.log("   - Open Source License: MIT");
  console.log("");
  console.log("4. For Standard-Json-Input, use the file generated at:");

  // Generate Standard-Json-Input
  const buildInfoDir = path.join(__dirname, "../artifacts/build-info");
  if (fs.existsSync(buildInfoDir)) {
    const buildInfoFiles = fs.readdirSync(buildInfoDir);
    if (buildInfoFiles.length > 0) {
      const latestBuildInfo = buildInfoFiles[buildInfoFiles.length - 1];
      console.log(`   artifacts/build-info/${latestBuildInfo}`);
    }
  } else {
    console.log("   (Build info not found - run 'npx hardhat compile' first)");
  }
  console.log("");

  // === Summary ===
  console.log("=".repeat(60));
  console.log("VERIFICATION SUMMARY");
  console.log("=".repeat(60));
  console.log("");

  const checks = [
    ["Time reward rates initialized", allRatesCorrect],
    ["Special NFT start ID = 2340", startId === 2340n],
    ["Special NFT end ID = 2700", endId === 2700n],
  ];

  let allPassed = true;
  for (const [name, passed] of checks) {
    const status = passed ? "✅ PASS" : "❌ FAIL";
    if (!passed) allPassed = false;
    console.log(`  ${status}: ${name}`);
  }
  console.log("");

  if (allPassed) {
    console.log("✅ All V3 state verifications passed!");
    console.log("");
    console.log("Next steps:");
    console.log("1. Verify implementation contract source on Roguescan");
    console.log("2. Test deposit: npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 1000");
    console.log("3. Test withdrawal: npx hardhat run scripts/withdraw-time-rewards.js --network rogueMainnet");
    console.log("4. Deposit full pool: npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 5614272000");
  } else {
    console.log("❌ Some V3 state verifications failed!");
    console.log("   Please check the upgrade was successful.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
