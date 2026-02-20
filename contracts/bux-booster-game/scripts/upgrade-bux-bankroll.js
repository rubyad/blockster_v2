/**
 * Upgrade BUXBankroll — via Hardhat runner
 *
 * Upgrades the UUPS proxy to new implementation with Plinko additions.
 * No reinitializer needed (only new state + functions added).
 *
 * Usage:
 *   npx hardhat run scripts/upgrade-bux-bankroll.js --network rogueMainnet
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY set in .env (must be proxy owner)
 *   - Deployer has ROGUE for gas
 *   - npx hardhat compile
 */

const { ethers } = require("hardhat");

const BUX_BANKROLL_PROXY = "0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("=== BUXBankroll Upgrade ===");
  console.log("Deployer:", deployer.address);
  console.log("Proxy:", BUX_BANKROLL_PROXY);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "ROGUE");

  // --- Pre-flight: Check current proxy owner ---
  console.log("\n--- Pre-flight: Checking proxy state ---");
  const proxy = await ethers.getContractAt("BUXBankroll", BUX_BANKROLL_PROXY);

  const currentOwner = await proxy.owner();
  console.log("  Owner:", currentOwner);
  if (currentOwner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error("ERROR: Deployer is NOT the proxy owner.");
    process.exit(1);
  }

  const lpPrice = await proxy.getLPPrice();
  const buxToken = await proxy.buxToken();
  console.log("  LP Price:", lpPrice.toString());
  console.log("  BUX Token:", buxToken);

  // --- Step 1: Deploy new implementation ---
  console.log("\n--- Step 1: Deploy new BUXBankroll Implementation ---");
  const nonce = await deployer.getNonce();
  console.log("  Nonce:", nonce);

  const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
  const newImpl = await BUXBankroll.deploy({
    gasLimit: 5000000,
    nonce: nonce,
  });
  await newImpl.waitForDeployment();

  const newImplAddress = await newImpl.getAddress();
  console.log("  New implementation deployed at:", newImplAddress);

  // --- Step 2: Upgrade proxy ---
  console.log("\n--- Step 2: Upgrade proxy to new implementation ---");

  const tx = await proxy.upgradeToAndCall(newImplAddress, "0x", {
    gasLimit: 500000,
    nonce: nonce + 1,
  });
  console.log("  Tx hash:", tx.hash);
  console.log("  Waiting for confirmation...");
  const receipt = await tx.wait();
  console.log("  Upgrade confirmed in block:", receipt.blockNumber);

  // --- Step 3: Post-upgrade verification ---
  console.log("\n--- Step 3: Post-upgrade Verification ---");

  const postOwner = await proxy.owner();
  const postBuxToken = await proxy.buxToken();
  const postLpPrice = await proxy.getLPPrice();
  console.log("  Owner:", postOwner, postOwner === currentOwner ? "(unchanged)" : "CHANGED!");
  console.log("  BUX Token:", postBuxToken, postBuxToken === buxToken ? "(unchanged)" : "CHANGED!");
  console.log("  LP Price:", postLpPrice.toString());

  // Verify new Plinko functions exist
  try {
    const plinkoGame = await proxy.plinkoGame();
    console.log("  plinkoGame():", plinkoGame, "(new function works)");
  } catch (e) {
    console.error("  ERROR: plinkoGame() failed:", e.message);
  }

  try {
    const acc = await proxy.getPlinkoAccounting();
    console.log("  getPlinkoAccounting() totalBets:", acc[0].toString(), "(new function works)");
  } catch (e) {
    console.error("  ERROR: getPlinkoAccounting() failed:", e.message);
  }

  // --- Summary ---
  console.log("\n========================================");
  console.log("=== BUXBankroll Upgrade Complete ===");
  console.log("========================================");
  console.log("Proxy:              ", BUX_BANKROLL_PROXY);
  console.log("New implementation: ", newImplAddress);
  console.log("");
  console.log("NEXT STEPS:");
  console.log("1. Call setPlinkoGame(plinkoGameAddress) after PlinkoGame is deployed");
  console.log("");
  console.log("SAVE: BUX_BANKROLL_NEW_IMPL=" + newImplAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
