const { ethers } = require("hardhat");

/**
 * Upgrade NFTRewarder to V4 - Fix time reward calculation bug
 *
 * This script:
 * 1. Deploys the new V4 implementation contract
 * 2. Upgrades the proxy using upgradeTo (no initializer needed)
 *
 * BUG FIXED:
 * pendingTimeReward() was incorrectly dividing by 1e18:
 *   pending = (ratePerSecond * timeElapsed) / 1e18  <- WRONG
 *
 * ratePerSecond is already in wei (e.g., 1.062454e18 for Aurora),
 * so multiplying by seconds gives wei. The /1e18 was making
 * pending ~1e18 times smaller than it should be.
 *
 * CORRECT formula:
 *   pending = ratePerSecond * timeElapsed  <- Returns wei
 *
 * Run with: npx hardhat run scripts/upgrade-nftrewarder-v4.js --network rogueMainnet
 */
async function main() {
  const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  console.log("=".repeat(60));
  console.log("NFTRewarder V4 Upgrade - Fix Time Reward Calculation Bug");
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
  console.log("Owner verified");
  console.log("");

  // Get pending reward BEFORE upgrade for comparison
  console.log("Step 1: Checking current (buggy) pending reward for token 2341...");
  try {
    const [pendingBefore] = await proxy.pendingTimeReward(2341);
    console.log("Pending before (buggy):", pendingBefore.toString(), "wei");
    console.log("Pending before (formatted):", ethers.formatEther(pendingBefore), "ROGUE");
  } catch (e) {
    console.log("Could not check pending before:", e.message);
  }
  console.log("");

  // Deploy new implementation
  console.log("Step 2: Deploying new V4 implementation contract...");
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const newImpl = await NFTRewarder.deploy();
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("New implementation deployed at:", newImplAddress);
  console.log("");

  // Upgrade proxy (no initializer needed for this fix)
  console.log("Step 3: Upgrading proxy to V4 implementation...");
  console.log("Proxy address:", PROXY_ADDRESS);
  console.log("New implementation:", newImplAddress);
  console.log("");

  try {
    // Use upgradeTo instead of upgradeToAndCall since no initializer needed
    const tx = await proxy.upgradeToAndCall(newImplAddress, "0x", {
      gasLimit: 3000000
    });
    console.log("Upgrade TX submitted:", tx.hash);
    console.log("Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log("Upgrade confirmed in block:", receipt.blockNumber);
    console.log("");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    throw error;
  }

  // Verify the fix by checking pending reward AFTER upgrade
  console.log("Step 4: Verifying fix - checking pending reward for token 2341...");
  try {
    const [pendingAfter, ratePerSecond] = await proxy.pendingTimeReward(2341);
    console.log("Pending after (fixed):", pendingAfter.toString(), "wei");
    console.log("Pending after (formatted):", ethers.formatEther(pendingAfter), "ROGUE");
    console.log("Rate per second:", ethers.formatEther(ratePerSecond), "ROGUE/sec");

    // Sanity check - pending should be > 1 ROGUE (it was showing 0.00000001 before)
    if (pendingAfter > ethers.parseEther("1")) {
      console.log("Time reward calculation is now correct!");
    } else {
      console.log("WARNING: Pending still seems too low. Manual verification needed.");
    }
  } catch (e) {
    console.log("Could not verify pending after:", e.message);
  }
  console.log("");

  console.log("=".repeat(60));
  console.log("NFTRewarder V4 Upgrade Complete!");
  console.log("=".repeat(60));
  console.log("");
  console.log("New Implementation Address:", newImplAddress);
  console.log("(Save this for Roguescan verification)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
