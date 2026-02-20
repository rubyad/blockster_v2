/**
 * Verify BUXBankroll deployment — checks all initial state values
 *
 * Usage:
 *   BUX_BANKROLL_PROXY=0x... npx hardhat run scripts/verify-bux-bankroll.js --network rogueMainnet
 */

const { ethers } = require("hardhat");

const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

async function main() {
  const proxyAddress = process.env.BUX_BANKROLL_PROXY;
  if (!proxyAddress) {
    console.error("ERROR: Set BUX_BANKROLL_PROXY env var to the deployed proxy address");
    process.exit(1);
  }

  const [deployer] = await ethers.getSigners();
  console.log("=== BUXBankroll Verification ===");
  console.log("Proxy:", proxyAddress);
  console.log("Deployer:", deployer.address);

  const bankroll = await ethers.getContractAt("BUXBankroll", proxyAddress);

  let passed = 0;
  let failed = 0;

  function check(label, actual, expected) {
    const actualStr = String(actual);
    const expectedStr = String(expected);
    const match = actualStr.toLowerCase() === expectedStr.toLowerCase();
    if (match) {
      console.log(`  PASS  ${label}: ${actualStr}`);
      passed++;
    } else {
      console.log(`  FAIL  ${label}: got ${actualStr}, expected ${expectedStr}`);
      failed++;
    }
  }

  // --- 1. Ownership ---
  console.log("\n--- Ownership ---");
  const owner = await bankroll.owner();
  check("owner == deployer", owner, deployer.address);

  // --- 2. BUX Token ---
  console.log("\n--- BUX Token ---");
  const buxToken = await bankroll.buxToken();
  check("buxToken", buxToken, BUX_TOKEN);

  // --- 3. LP Token Metadata ---
  console.log("\n--- LP Token ---");
  const name = await bankroll.name();
  check("name", name, "BUX Bankroll");

  const symbol = await bankroll.symbol();
  check("symbol", symbol, "LP-BUX");

  const decimals = await bankroll.decimals();
  check("decimals", decimals, 18);

  const totalSupply = await bankroll.totalSupply();
  check("totalSupply", totalSupply, 0);

  // --- 4. LP Price ---
  console.log("\n--- LP Price ---");
  const lpPrice = await bankroll.getLPPrice();
  check("lpPrice (1e18 = 1:1)", lpPrice, ethers.parseEther("1"));

  // --- 5. House Balance ---
  console.log("\n--- House Balance ---");
  const [totalBalance, liability, unsettledBets, netBalance, poolTokenSupply, poolTokenPrice] =
    await bankroll.getHouseInfo();
  check("totalBalance", totalBalance, 0);
  check("liability", liability, 0);
  check("unsettledBets", unsettledBets, 0);
  check("netBalance", netBalance, 0);
  check("poolTokenSupply", poolTokenSupply, 0);
  check("poolTokenPrice", poolTokenPrice, ethers.parseEther("1"));

  // --- 6. Bet Config ---
  console.log("\n--- Bet Config ---");
  const maxBetDivisor = await bankroll.maximumBetSizeDivisor();
  check("maximumBetSizeDivisor", maxBetDivisor, 1000);

  // --- 7. Referral System ---
  console.log("\n--- Referral System ---");
  const referralBps = await bankroll.referralBasisPoints();
  check("referralBasisPoints", referralBps, 20);

  const referralAdmin = await bankroll.referralAdmin();
  check("referralAdmin (unset)", referralAdmin, ZERO_ADDRESS);

  const totalRefRewards = await bankroll.getTotalReferralRewardsPaid();
  check("totalReferralRewardsPaid", totalRefRewards, 0);

  // --- 8. Game Authorization ---
  console.log("\n--- Game Authorization ---");
  const plinkoGame = await bankroll.plinkoGame();
  check("plinkoGame (unset)", plinkoGame, ZERO_ADDRESS);

  // --- 9. Pause State ---
  console.log("\n--- Pause State ---");
  const paused = await bankroll.paused();
  check("paused", paused, false);

  // --- Summary ---
  console.log("\n========================================");
  console.log(`=== Results: ${passed} passed, ${failed} failed ===`);
  console.log("========================================");

  if (failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
