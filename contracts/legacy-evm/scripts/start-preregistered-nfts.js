const { ethers } = require("hardhat");

/**
 * Start time rewards for pre-registered NFTs (2340-2342)
 *
 * These 3 NFTs were registered before V3 upgrade and need manual start.
 * Special NFTs (2340-2700) normally auto-start on registration, but these
 * were registered before the auto-start logic was added.
 *
 * Usage:
 *   npx hardhat run scripts/start-preregistered-nfts.js --network rogueMainnet
 */
async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  // Pre-registered NFTs that need manual time reward start
  const PRE_REGISTERED_NFTS = [2340, 2341, 2342];

  console.log("=".repeat(60));
  console.log("Start Time Rewards for Pre-Registered NFTs");
  console.log("=".repeat(60));
  console.log("NFTs to start:", PRE_REGISTERED_NFTS.join(", "));
  console.log("");

  const [deployer] = await ethers.getSigners();
  console.log("Admin account:", deployer.address);

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  // Check admin
  const admin = await NFTRewarder.admin();
  if (admin.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error(`Only admin can start time rewards. Admin: ${admin}, Deployer: ${deployer.address}`);
  }
  console.log("✅ Deployer is contract admin");
  console.log("");

  // Check pool has funds
  const poolRemaining = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Time reward pool remaining:", ethers.formatEther(poolRemaining), "ROGUE");
  if (poolRemaining === 0n) {
    throw new Error("Time reward pool is empty! Deposit funds first.");
  }
  console.log("");

  // Process each NFT
  const hostessNames = ["Penelope", "Mia", "Cleo", "Sophia", "Luna", "Aurora", "Scarlett", "Vivienne"];

  for (const tokenId of PRE_REGISTERED_NFTS) {
    console.log(`Processing NFT #${tokenId}...`);

    // Check if registered
    const metadata = await NFTRewarder.nftMetadata(tokenId);
    if (!metadata.registered) {
      console.log(`  ⚠️  NFT #${tokenId} is NOT registered, skipping`);
      continue;
    }

    const hostessIndex = metadata.hostessIndex;
    const hostessName = hostessNames[hostessIndex] || `Unknown(${hostessIndex})`;
    console.log(`  Hostess: ${hostessName} (index ${hostessIndex})`);
    console.log(`  Owner: ${metadata.owner}`);

    // Check if special NFT (should be in range 2340-2700)
    const [isSpecial, hasStarted] = await NFTRewarder.isSpecialNFT(tokenId);
    console.log(`  Is Special NFT: ${isSpecial}`);
    console.log(`  Time rewards started: ${hasStarted}`);

    if (!isSpecial) {
      console.log(`  ⚠️  NFT #${tokenId} is NOT in special range (2340-2700), skipping`);
      continue;
    }

    if (hasStarted) {
      console.log(`  ✅ NFT #${tokenId} time rewards already started, skipping`);
      continue;
    }

    // Start time rewards
    console.log(`  Starting time rewards for NFT #${tokenId}...`);
    try {
      const tx = await NFTRewarder.startTimeRewardManual(tokenId, { gasLimit: 200000 });
      console.log(`  TX Hash: ${tx.hash}`);

      const receipt = await tx.wait();
      console.log(`  ✅ Started in block ${receipt.blockNumber}`);

      // Verify start
      const timeRewardInfo = await NFTRewarder.getTimeRewardInfo(tokenId);
      console.log(`  Start time: ${new Date(Number(timeRewardInfo[0]) * 1000).toISOString()}`);
      console.log(`  End time: ${new Date(Number(timeRewardInfo[1]) * 1000).toISOString()}`);
      console.log(`  Rate per second: ${ethers.formatEther(timeRewardInfo[2])} ROGUE`);
    } catch (error) {
      console.error(`  ❌ Failed to start NFT #${tokenId}:`, error.message);
    }

    console.log("");
  }

  // Final summary
  console.log("=".repeat(60));
  console.log("Summary");
  console.log("=".repeat(60));

  const poolAfter = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Time reward pool remaining:", ethers.formatEther(poolAfter), "ROGUE");
  console.log("");

  // Show status of all pre-registered NFTs
  console.log("Pre-registered NFT Status:");
  for (const tokenId of PRE_REGISTERED_NFTS) {
    const [isSpecial, hasStarted] = await NFTRewarder.isSpecialNFT(tokenId);
    const status = hasStarted ? "✅ Started" : "❌ Not Started";
    console.log(`  NFT #${tokenId}: ${status}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
