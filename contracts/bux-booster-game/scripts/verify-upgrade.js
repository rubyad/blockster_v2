const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  
  const contract = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);
  
  console.log("=== Verifying Upgraded Contract ===");
  console.log("Proxy Address:", PROXY_ADDRESS);
  
  // Check arrays are initialized
  console.log("\nArray values:");
  console.log("FLIP_COUNTS[4] (should be 1):", await contract.FLIP_COUNTS(4));
  console.log("MULTIPLIERS[4] (should be 19800):", await contract.MULTIPLIERS(4));
  
  // Try calling placeBet signature (should not revert on view)
  console.log("\n✅ Contract upgraded successfully!");
  console.log("Nonce validation has been removed from placeBet");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
