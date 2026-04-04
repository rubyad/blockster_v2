/**
 * Fix misregistered hostess indices for tokens #1, #2, #3
 * They were registered as hostess_index=7 (30x) but should be hostess_index=5 (50x)
 */

const { ethers } = require("hardhat");

const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

async function main() {
  console.log("=== Fixing Hostess Indices ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Owner:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE\n");

  // Connect to contract
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const nftRewarder = NFTRewarder.attach(NFT_REWARDER_ADDRESS).connect(deployer);

  // Check current state
  console.log("Current state:");
  const totalPointsBefore = await nftRewarder.totalMultiplierPoints();
  console.log("  totalMultiplierPoints:", totalPointsBefore.toString());

  // Check tokens #1, #2, #3
  for (const tokenId of [1, 2, 3]) {
    const metadata = await nftRewarder.nftMetadata(tokenId);
    console.log(`  Token #${tokenId}: hostessIndex=${metadata.hostessIndex}, registered=${metadata.registered}`);
  }

  // Fix tokens #1, #2, #3 - change from 7 to 5
  console.log("\nFixing hostess indices...");
  const tokenIds = [1, 2, 3];
  const correctIndices = [5, 5, 5];  // Aurora Seductra (50x)

  const tx = await nftRewarder.batchFixHostessIndex(tokenIds, correctIndices, {
    gasLimit: 500000
  });
  console.log("TX:", tx.hash);
  await tx.wait();
  console.log("✓ Fixed!\n");

  // Verify fix
  console.log("After fix:");
  const totalPointsAfter = await nftRewarder.totalMultiplierPoints();
  console.log("  totalMultiplierPoints:", totalPointsAfter.toString());
  console.log("  Expected: 109390");
  console.log("  Match:", totalPointsAfter.toString() === "109390" ? "✓ Yes" : "✗ No");

  for (const tokenId of [1, 2, 3]) {
    const metadata = await nftRewarder.nftMetadata(tokenId);
    console.log(`  Token #${tokenId}: hostessIndex=${metadata.hostessIndex}, registered=${metadata.registered}`);
  }
}

main().catch(console.error);
