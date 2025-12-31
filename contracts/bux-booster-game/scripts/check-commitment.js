const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const COMMITMENT_HASH = "0xe9c40ea12c8a65f28abb5c43f75c1f20e7908a88991e36073e82fcef6d24c16a";
  const PLAYER = "0xB6B4cb36ce26D62fE02402EF43cB489183B2A137";

  console.log("=== Checking Commitment ===");
  const game = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  try {
    const commitment = await game.commitments(COMMITMENT_HASH);
    console.log("Commitment found:");
    console.log("  Player:", commitment.player);
    console.log("  Nonce:", commitment.nonce.toString());
    console.log("  Timestamp:", new Date(Number(commitment.timestamp) * 1000).toISOString());
    console.log("  Used:", commitment.used);
    console.log("  Server Seed:", commitment.serverSeed);

    if (commitment.player === "0x0000000000000000000000000000000000000000") {
      console.log("\n❌ Commitment NOT found - this is the problem!");
      console.log("The server needs to call submitCommitment() BEFORE the player places a bet.");
    } else if (commitment.player.toLowerCase() !== PLAYER.toLowerCase()) {
      console.log("\n❌ Commitment belongs to different player!");
      console.log("Expected:", PLAYER);
    } else if (commitment.used) {
      console.log("\n❌ Commitment already used!");
    } else {
      console.log("\n✅ Commitment valid and ready to use");
    }
  } catch (error) {
    console.error("Error reading commitment:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
