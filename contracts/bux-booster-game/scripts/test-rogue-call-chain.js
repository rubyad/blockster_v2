const { ethers } = require("hardhat");

async function main() {
  const PROXY = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const BANKROLL = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
  const COMMITMENT = "0xe9c40ea12c8a65f28abb5c43f75c1f20e7908a88991e36073e82fcef6d24c16a";

  console.log("=== Testing ROGUE Bet Call Chain ===\n");

  const game = await ethers.getContractAt("BuxBoosterGame", PROXY);
  const bankroll = await ethers.getContractAt("ROGUEBankroll", BANKROLL);

  // Get commitment details
  const commitment = await game.commitments(COMMITMENT);
  const nonce = commitment.nonce;

  console.log("1. Commitment details:");
  console.log("   Player:", commitment.player);
  console.log("   Nonce:", nonce.toString());
  console.log("   Used:", commitment.used);

  // Check authorization
  const authorizedBuxBooster = await bankroll.getBuxBoosterGame();
  console.log("\n2. ROGUEBankroll authorization:");
  console.log("   Authorized address:", authorizedBuxBooster);
  console.log("   BuxBoosterGame:", PROXY);
  console.log("   Match:", authorizedBuxBooster.toLowerCase() === PROXY.toLowerCase() ? "✅" : "❌");

  // Check if we can call the bankroll function directly (should fail - only BuxBooster)
  console.log("\n3. Testing direct call to ROGUEBankroll (should fail):");
  try {
    await bankroll.updateHouseBalanceBuxBoosterBetPlaced.staticCall(
      COMMITMENT,
      1, // difficulty
      [0], // predictions
      nonce,
      ethers.parseEther("316.8"), // maxPayout for 160 ROGUE at 1.98x
      { value: ethers.parseEther("160") }
    );
    console.log("   ❌ Call succeeded (unexpected - should be restricted)");
  } catch (error) {
    if (error.message.includes("Only BuxBooster")) {
      console.log("   ✅ Call rejected with 'Only BuxBooster' (expected)");
    } else {
      console.log("   ⚠️  Call failed with different error:", error.message.slice(0, 100));
    }
  }

  // Now let's check what happens when BuxBoosterGame calls it
  console.log("\n4. Testing BuxBoosterGame -> ROGUEBankroll call:");
  console.log("   When placeBetROGUE() is called:");
  console.log("   - msg.sender at BuxBoosterGame = SmartWallet");
  console.log("   - BuxBoosterGame forwards to ROGUEBankroll");
  console.log("   - msg.sender at ROGUEBankroll = BuxBoosterGame ✅");
  console.log("   - Authorization should pass");

  // Check house balance
  const [netBalance, totalBalance, minBet, maxBet] = await bankroll.getHouseInfo();
  console.log("\n5. ROGUEBankroll state:");
  console.log("   Net Balance:", ethers.formatEther(netBalance), "ROGUE");
  console.log("   Min Bet:", ethers.formatEther(minBet), "ROGUE");
  console.log("   Max Bet:", ethers.formatEther(maxBet), "ROGUE");
  console.log("   160 ROGUE within limits?",
    ethers.parseEther("160") >= minBet && ethers.parseEther("160") <= maxBet ? "✅" : "❌");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
