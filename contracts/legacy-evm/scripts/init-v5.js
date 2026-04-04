const { ethers } = require("hardhat");

async function main() {
  const BUX_BOOSTER_GAME_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  console.log("Initializing BuxBoosterGame V5...");
  console.log("BuxBoosterGame proxy:", BUX_BOOSTER_GAME_ADDRESS);
  console.log("ROGUEBankroll address:", ROGUE_BANKROLL_ADDRESS);

  const BuxBoosterGame = await ethers.getContractAt("BuxBoosterGame", BUX_BOOSTER_GAME_ADDRESS);

  // Check current rogueBankroll value
  const currentBankroll = await BuxBoosterGame.rogueBankroll();
  console.log("\nCurrent rogueBankroll address:", currentBankroll);

  if (currentBankroll.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase()) {
    console.log("✓ ROGUEBankroll address already set correctly!");
    return;
  }

  // Initialize V5
  console.log("\nCalling initializeV5...");
  const tx = await BuxBoosterGame.initializeV5(ROGUE_BANKROLL_ADDRESS);
  console.log("Transaction hash:", tx.hash);

  console.log("Waiting for confirmation...");
  await tx.wait();

  // Verify
  const newBankroll = await BuxBoosterGame.rogueBankroll();
  console.log("\n✓ ROGUEBankroll address set to:", newBankroll);

  if (newBankroll.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase()) {
    console.log("✓ Successfully initialized BuxBoosterGame V5!");
  } else {
    console.log("✗ Error: Address mismatch after initialization");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
