/**
 * Deploy PlinkoGame as UUPS proxy + full setup
 *
 * Deploys PlinkoGame, sets all 9 payout tables, links bankrolls,
 * enables BUX token, and wires setPlinkoGame on both bankrolls.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-plinko-game.js --network rogueMainnet
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY in .env
 *   - Deployer has ROGUE for gas
 *   - npx hardhat compile
 */

const { ethers, upgrades } = require("hardhat");

const BUX_BANKROLL_PROXY = "0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630";
const ROGUE_BANKROLL_PROXY = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

// All 9 payout tables (basis points, 10000 = 1.0x)
const PAYOUT_TABLES = [
  [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],           // 0: 8-Low
  [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],           // 1: 8-Med
  [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],              // 2: 8-High
  [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000], // 3: 12-Low
  [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000], // 4: 12-Med
  [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],    // 5: 12-High
  [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000], // 6: 16-Low
  [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000], // 7: 16-Med
  [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000], // 8: 16-High
];

const CONFIG_LABELS = [
  "8-Low", "8-Med", "8-High",
  "12-Low", "12-Med", "12-High",
  "16-Low", "16-Med", "16-High",
];

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("=== PlinkoGame Deployment ===");
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  // --- Step 1: Deploy PlinkoGame as UUPS proxy ---
  console.log("\n--- Step 1: Deploy PlinkoGame UUPS Proxy ---");
  const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
  const plinko = await upgrades.deployProxy(PlinkoGame, [], {
    initializer: "initialize",
    kind: "uups",
    timeout: 300000,
    pollingInterval: 5000,
  });
  await plinko.waitForDeployment();

  const plinkoProxy = await plinko.getAddress();
  const plinkoImpl = await upgrades.erc1967.getImplementationAddress(plinkoProxy);
  console.log("  Proxy:          ", plinkoProxy);
  console.log("  Implementation: ", plinkoImpl);
  console.log("  Owner:          ", await plinko.owner());

  // --- Step 2: Set payout tables ---
  console.log("\n--- Step 2: Set 9 Payout Tables ---");
  for (let i = 0; i < 9; i++) {
    const tx = await plinko.setPayoutTable(i, PAYOUT_TABLES[i]);
    await tx.wait();
    console.log(`  [${i}] ${CONFIG_LABELS[i]}: set (max ${PAYOUT_TABLES[i][0]} bps)`);
  }

  // --- Step 3: Link contracts ---
  console.log("\n--- Step 3: Link Contracts ---");

  console.log("  Setting BUXBankroll...");
  let tx = await plinko.setBUXBankroll(BUX_BANKROLL_PROXY);
  await tx.wait();
  console.log("  BUXBankroll:", BUX_BANKROLL_PROXY);

  console.log("  Setting ROGUEBankroll...");
  tx = await plinko.setROGUEBankroll(ROGUE_BANKROLL_PROXY);
  await tx.wait();
  console.log("  ROGUEBankroll:", ROGUE_BANKROLL_PROXY);

  console.log("  Setting BUX Token...");
  tx = await plinko.setBUXToken(BUX_TOKEN);
  await tx.wait();
  console.log("  BUX Token:", BUX_TOKEN);

  console.log("  Enabling BUX token...");
  tx = await plinko.configureToken(BUX_TOKEN, true);
  await tx.wait();
  console.log("  BUX token enabled");

  // --- Step 4: Wire setPlinkoGame on bankrolls ---
  console.log("\n--- Step 4: Wire setPlinkoGame on Bankrolls ---");

  // Try ROGUEBankroll
  try {
    const rogueBankroll = await ethers.getContractAt(
      "contracts/ROGUEBankroll.sol:ROGUEBankroll",
      ROGUE_BANKROLL_PROXY
    );
    const rogueOwner = await rogueBankroll.owner();
    if (rogueOwner.toLowerCase() === deployer.address.toLowerCase()) {
      tx = await rogueBankroll.setPlinkoGame(plinkoProxy);
      await tx.wait();
      console.log("  ROGUEBankroll.setPlinkoGame:", plinkoProxy, "OK");
    } else {
      console.log("  ROGUEBankroll: owner is", rogueOwner, "- skipping (different key needed)");
    }
  } catch (e) {
    console.log("  ROGUEBankroll.setPlinkoGame failed:", e.message.slice(0, 100));
  }

  // Try BUXBankroll
  try {
    const buxBankroll = await ethers.getContractAt("BUXBankroll", BUX_BANKROLL_PROXY);
    const buxOwner = await buxBankroll.owner();
    if (buxOwner.toLowerCase() === deployer.address.toLowerCase()) {
      tx = await buxBankroll.setPlinkoGame(plinkoProxy);
      await tx.wait();
      console.log("  BUXBankroll.setPlinkoGame:", plinkoProxy, "OK");
    } else {
      console.log("  BUXBankroll: owner is", buxOwner, "- skipping (different key needed)");
    }
  } catch (e) {
    console.log("  BUXBankroll.setPlinkoGame failed:", e.message.slice(0, 100));
  }

  // --- Step 5: Verification ---
  console.log("\n--- Step 5: Verification ---");
  console.log("  owner():", await plinko.owner());
  console.log("  buxBankroll():", await plinko.buxBankroll());
  console.log("  rogueBankroll():", await plinko.rogueBankroll());
  console.log("  buxToken():", await plinko.buxToken());
  console.log("  tokenConfigs(BUX):", await plinko.tokenConfigs(BUX_TOKEN));
  console.log("  totalBetsPlaced():", (await plinko.totalBetsPlaced()).toString());

  const maxBet0 = await plinko.getMaxBet(0);
  const maxBet8 = await plinko.getMaxBet(8);
  console.log("  getMaxBet(0) 8-Low:", ethers.formatEther(maxBet0), "BUX");
  console.log("  getMaxBet(8) 16-High:", ethers.formatEther(maxBet8), "BUX");

  // --- Summary ---
  console.log("\n========================================");
  console.log("=== PlinkoGame Deployment Complete ===");
  console.log("========================================");
  console.log("Proxy:          ", plinkoProxy);
  console.log("Implementation: ", plinkoImpl);
  console.log("Owner:          ", deployer.address);
  console.log("BUXBankroll:    ", BUX_BANKROLL_PROXY);
  console.log("ROGUEBankroll:  ", ROGUE_BANKROLL_PROXY);
  console.log("BUX Token:      ", BUX_TOKEN);
  console.log("");
  console.log("REMAINING SETUP:");
  console.log("1. Set settler:  plinko.setSettler(SETTLER_ADDRESS)");
  console.log("2. If BUXBankroll.setPlinkoGame was skipped, run it with the BUXBankroll owner key");
  console.log("3. If ROGUEBankroll.setPlinkoGame was skipped, run it with the ROGUEBankroll owner key");
  console.log("");
  console.log("SAVE THESE ADDRESSES:");
  console.log("  PLINKO_GAME_PROXY=" + plinkoProxy);
  console.log("  PLINKO_GAME_IMPL=" + plinkoImpl);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
