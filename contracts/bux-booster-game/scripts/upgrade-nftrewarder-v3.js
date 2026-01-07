const { ethers } = require("hardhat");

/**
 * Upgrade NFTRewarder to V3 for Time-Based Rewards
 *
 * This script:
 * 1. Deploys the new V3 implementation contract
 * 2. Upgrades the proxy using upgradeToAndCall with initializeV3()
 *
 * initializeV3() sets the timeRewardRatesPerSecond array with HARDCODED values:
 * - Penelope (0): 2.125 ROGUE/sec
 * - Mia (1): 1.912 ROGUE/sec
 * - Cleo (2): 1.700 ROGUE/sec
 * - Sophia (3): 1.487 ROGUE/sec
 * - Luna (4): 1.275 ROGUE/sec
 * - Aurora (5): 1.062 ROGUE/sec
 * - Scarlett (6): 0.850 ROGUE/sec
 * - Vivienne (7): 0.637 ROGUE/sec
 *
 * These rates are pre-calculated in the contract based on:
 * ROGUE_PER_NFT_TYPE / 15,552,000 seconds (180 days) * 1e18
 *
 * Run with: npx hardhat run scripts/upgrade-nftrewarder-v3.js --network rogueMainnet
 */
async function main() {
  const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  console.log("=".repeat(60));
  console.log("NFTRewarder V3 Upgrade - Time-Based Rewards");
  console.log("=".repeat(60));
  console.log("");

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  // Check deployer balance for gas
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ROGUE");
  console.log("");

  // Get current implementation
  const proxy = await ethers.getContractAt("NFTRewarder", PROXY_ADDRESS);

  // Check current owner
  const currentOwner = await proxy.owner();
  console.log("Current proxy owner:", currentOwner);

  if (currentOwner.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error(`Deployer (${deployer.address}) is not the proxy owner (${currentOwner})`);
  }
  console.log("✅ Deployer is proxy owner");
  console.log("");

  // Deploy new implementation
  console.log("Step 1: Deploying new V3 implementation contract...");
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const newImpl = await NFTRewarder.deploy();
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("✅ New implementation deployed at:", newImplAddress);
  console.log("");

  // Encode initializeV3() call data
  // Note: initializeV3 takes NO arguments - the time reward rates are HARDCODED
  // in the contract function itself as pre-calculated constants
  console.log("Step 2: Preparing initializeV3() call data...");
  const initializeV3Data = proxy.interface.encodeFunctionData("initializeV3", []);
  console.log("initializeV3 call data:", initializeV3Data);
  console.log("");

  // Upgrade proxy with initializeV3
  console.log("Step 3: Upgrading proxy to V3 implementation with initializeV3()...");
  console.log("Proxy address:", PROXY_ADDRESS);
  console.log("New implementation:", newImplAddress);
  console.log("");

  try {
    const tx = await proxy.upgradeToAndCall(newImplAddress, initializeV3Data, {
      gasLimit: 5000000
    });
    console.log("Upgrade TX submitted:", tx.hash);
    console.log("Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log("✅ Upgrade confirmed in block:", receipt.blockNumber);
    console.log("");
  } catch (error) {
    console.error("❌ Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    throw error;
  }

  // Verify V3 initialization by checking time reward rates
  console.log("Step 4: Verifying V3 initialization...");
  try {
    // Check all 8 time reward rates
    console.log("Time reward rates per second (scaled by 1e18):");
    const hostessNames = ["Penelope", "Mia", "Cleo", "Sophia", "Luna", "Aurora", "Scarlett", "Vivienne"];
    for (let i = 0; i < 8; i++) {
      const rate = await proxy.timeRewardRatesPerSecond(i);
      console.log(`  ${hostessNames[i]} (${i}): ${rate.toString()}`);
    }

    // Verify Penelope rate is correct (2_125_029_000_000_000_000)
    const penelopeRate = await proxy.timeRewardRatesPerSecond(0);
    if (penelopeRate !== 2125029000000000000n) {
      throw new Error(`Penelope rate mismatch! Expected 2125029000000000000, got ${penelopeRate}`);
    }
    console.log("✅ Time reward rates initialized correctly");
    console.log("");

    // Check special NFT range
    const startId = await proxy.SPECIAL_NFT_START_ID();
    const endId = await proxy.SPECIAL_NFT_END_ID();
    console.log("Special NFT range:", startId.toString(), "-", endId.toString());

    // Check time reward pool (should be 0 before deposit)
    const poolRemaining = await proxy.timeRewardPoolRemaining();
    console.log("Time reward pool remaining:", ethers.formatEther(poolRemaining), "ROGUE");
    console.log("");

  } catch (e) {
    console.error("❌ V3 verification failed:", e.message);
    throw e;
  }

  console.log("=".repeat(60));
  console.log("NFTRewarder V3 Upgrade Complete!");
  console.log("=".repeat(60));
  console.log("");
  console.log("Next steps:");
  console.log("1. Verify contract on Roguescan:");
  console.log("   npx hardhat run scripts/verify-nftrewarder-v3.js --network rogueMainnet");
  console.log("");
  console.log("2. Test deposit with small amount:");
  console.log("   npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 1000");
  console.log("");
  console.log("3. Test withdrawal works:");
  console.log("   npx hardhat run scripts/withdraw-time-rewards.js --network rogueMainnet");
  console.log("");
  console.log("4. Once verified, deposit full pool (5,614,272,000 ROGUE):");
  console.log("   npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 5614272000");
  console.log("");
  console.log("New Implementation Address:", newImplAddress);
  console.log("(Save this for Roguescan verification)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
