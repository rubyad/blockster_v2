const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const game = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  console.log("=== Checking FLIP_COUNTS array ===");
  for (let i = 0; i < 9; i++) {
    try {
      const count = await game.FLIP_COUNTS(i);
      console.log(`FLIP_COUNTS[${i}]:`, count.toString());
    } catch (error) {
      console.log(`FLIP_COUNTS[${i}]: ERROR -`, error.message);
    }
  }

  console.log("\n=== Checking difficulty 1 (1.98x multiplier) ===");
  const difficulty = 1;
  const diffIndex = difficulty < 0 ? 4 + difficulty : 3 + difficulty;
  console.log("Difficulty:", difficulty);
  console.log("Calculated index:", diffIndex);
  const expectedFlips = await game.FLIP_COUNTS(diffIndex);
  console.log("Expected flips:", expectedFlips.toString());
  console.log("\nPredictions array has 1 element [0]");
  console.log("Match?", expectedFlips.toString() === "1" ? "✅ YES" : "❌ NO");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
