const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const ROGUE_BANKROLL = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  console.log("=== Checking BuxBoosterGame Configuration ===");
  const game = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  const rogueBankroll = await game.rogueBankroll();
  console.log("BuxBoosterGame.rogueBankroll:", rogueBankroll);
  console.log("Expected:", ROGUE_BANKROLL);
  console.log("Match:", rogueBankroll.toLowerCase() === ROGUE_BANKROLL.toLowerCase());

  console.log("\n=== Checking ROGUEBankroll Configuration ===");
  const bankroll = await ethers.getContractAt("ROGUEBankroll", ROGUE_BANKROLL);

  const buxBooster = await bankroll.getBuxBoosterGame();
  console.log("ROGUEBankroll.buxBoosterGame:", buxBooster);
  console.log("Expected:", PROXY_ADDRESS);
  console.log("Match:", buxBooster.toLowerCase() === PROXY_ADDRESS.toLowerCase());

  console.log("\n=== Checking ROGUEBankroll House Info ===");
  const [netBalance, totalBalance, minBet, maxBet] = await bankroll.getHouseInfo();
  console.log("Net Balance:", ethers.formatEther(netBalance), "ROGUE");
  console.log("Total Balance:", ethers.formatEther(totalBalance), "ROGUE");
  console.log("Min Bet:", ethers.formatEther(minBet), "ROGUE");
  console.log("Max Bet:", ethers.formatEther(maxBet), "ROGUE");

  console.log("\n=== Checking Max Bet for Difficulty 1 (1.98x) ===");
  const maxBetForDiff = await game.getMaxBetROGUE(1);
  console.log("Max Bet (difficulty 1):", ethers.formatEther(maxBetForDiff), "ROGUE");

  // Check the failed transaction
  console.log("\n=== Checking Failed Transaction ===");
  const tx = await ethers.provider.getTransaction("0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac");
  if (tx) {
    console.log("From:", tx.from);
    console.log("To:", tx.to);
    console.log("Value:", ethers.formatEther(tx.value), "ROGUE");
    console.log("Data (first 10 bytes):", tx.data.slice(0, 20));

    const receipt = await ethers.provider.getTransactionReceipt("0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac");
    console.log("Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("Gas Used:", receipt.gasUsed.toString());
  } else {
    console.log("Transaction not found");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
