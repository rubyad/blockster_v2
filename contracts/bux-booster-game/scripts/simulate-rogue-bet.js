const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const COMMITMENT_HASH = "0xe9c40ea12c8a65f28abb5c43f75c1f20e7908a88991e36073e82fcef6d24c16a";
  const WALLET = "0xB6B4cb36ce26D62fE02402EF43cB489183B2A137";

  console.log("=== Simulating placeBetROGUE call ===");

  const game = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  const amount = ethers.parseEther("160");
  const difficulty = 1;
  const predictions = [0];

  try {
    // Try to call statically (this will show the revert reason)
    await game.placeBetROGUE.staticCall(
      amount,
      difficulty,
      predictions,
      COMMITMENT_HASH,
      {
        value: amount
      }
    );

    console.log("✅ Transaction would succeed!");
    console.log("Estimated gas:", gasEstimate.toString());
  } catch (error) {
    console.log("❌ Transaction would revert!");
    console.log("Error:", error.message);

    // Try to get more details
    if (error.data) {
      console.log("\nError data:", error.data);

      // Try to decode the error
      const gameInterface = new ethers.Interface([
        "error InvalidToken()",
        "error BetAmountTooLow()",
        "error BetAmountTooHigh()",
        "error InvalidDifficulty()",
        "error InvalidPredictions()",
        "error InsufficientHouseBalance()",
        "error CommitmentNotFound()",
        "error CommitmentAlreadyUsed()",
        "error CommitmentWrongPlayer()",
        "error CommitmentWrongNonce()"
      ]);

      try {
        const decodedError = gameInterface.parseError(error.data);
        console.log("\n🔍 Decoded error:", decodedError.name);
      } catch (e) {
        console.log("\n❓ Could not decode error");
      }
    }

    // Check the raw error info
    if (error.error && error.error.error && error.error.error.message) {
      console.log("\nRaw error message:", error.error.error.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\nScript error:", error.message);
    process.exit(1);
  });
