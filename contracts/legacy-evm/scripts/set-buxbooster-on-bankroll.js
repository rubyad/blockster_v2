const { ethers, upgrades } = require("hardhat");

async function main() {
  const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
  const BUX_BOOSTER_GAME_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  console.log("Setting BuxBoosterGame address on ROGUEBankroll...");
  console.log("ROGUEBankroll:", ROGUE_BANKROLL_ADDRESS);
  console.log("BuxBoosterGame:", BUX_BOOSTER_GAME_ADDRESS);

  const ROGUEBankroll = await ethers.getContractAt("ROGUEBankroll", ROGUE_BANKROLL_ADDRESS);

  // Check current value
  const currentBuxBooster = await ROGUEBankroll.getBuxBoosterGame();
  console.log("\nCurrent BuxBoosterGame address:", currentBuxBooster);

  if (currentBuxBooster.toLowerCase() === BUX_BOOSTER_GAME_ADDRESS.toLowerCase()) {
    console.log("✓ BuxBoosterGame address already set correctly!");
    return;
  }

  // Set the BuxBoosterGame address
  console.log("\nCalling setBuxBoosterGame...");
  const tx = await ROGUEBankroll.setBuxBoosterGame(BUX_BOOSTER_GAME_ADDRESS);
  console.log("Transaction hash:", tx.hash);

  console.log("Waiting for confirmation...");
  await tx.wait();

  // Verify
  const newBuxBooster = await ROGUEBankroll.getBuxBoosterGame();
  console.log("\n✓ BuxBoosterGame address set to:", newBuxBooster);

  if (newBuxBooster.toLowerCase() === BUX_BOOSTER_GAME_ADDRESS.toLowerCase()) {
    console.log("✓ Successfully configured ROGUEBankroll!");
  } else {
    console.log("✗ Error: Address mismatch after setting");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
