/**
 * NFT Registration Script for NFTRewarder
 *
 * This script reads all NFTs from the High Rollers SQLite database
 * and registers them in the NFTRewarder contract on Rogue Chain.
 *
 * Prerequisites:
 * - NFTRewarder contract deployed on Rogue Chain
 * - Admin wallet with ROGUE for gas
 * - High Rollers database accessible
 *
 * Usage:
 *   cd contracts/bux-booster-game
 *   npx hardhat run scripts/register-all-nfts.js --network rogueMainnet
 */

const { ethers } = require("hardhat");
const Database = require('better-sqlite3');
const path = require('path');

// Configuration
const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
const DB_PATH = path.resolve(__dirname, "../../../high-rollers-nfts/data/highrollers.db");

// Batch size for registration (gas optimization)
// Note: 100 NFTs exceeds block gas limit on Rogue Chain, use smaller batches
const BATCH_SIZE = 25;

// Expected totals for verification
const EXPECTED_TOTAL_NFTS = 2341;
const EXPECTED_TOTAL_MULTIPLIER_POINTS = 109390;

// NFTRewarder ABI (minimal)
// NOTE: Parameter order is tokenIds, hostessIndices, owners (matches contract)
const NFT_REWARDER_ABI = [
  "function batchRegisterNFTs(uint256[] calldata tokenIds, uint8[] calldata hostessIndices, address[] calldata owners) external",
  "function totalRegisteredNFTs() view returns (uint256)",
  "function totalMultiplierPoints() view returns (uint256)",
  "function admin() view returns (address)",
  "function nftMetadata(uint256 tokenId) view returns (uint8 hostessIndex, bool registered, address owner)"
];

async function main() {
  console.log("=== NFT Registration Script for NFTRewarder ===\n");

  // Connect to database
  console.log("Connecting to High Rollers database...");
  console.log("DB Path:", DB_PATH);

  let db;
  try {
    db = new Database(DB_PATH, { readonly: true });
    console.log("✓ Database connected\n");
  } catch (error) {
    console.error("✗ Failed to connect to database:", error.message);
    console.log("\nMake sure the database exists at:", DB_PATH);
    process.exit(1);
  }

  // Get all NFTs from database
  console.log("Fetching all NFTs from database...");
  const nfts = db.prepare(`
    SELECT token_id, owner, hostess_index
    FROM nfts
    ORDER BY token_id ASC
  `).all();

  console.log(`✓ Found ${nfts.length} NFTs in database\n`);

  // Validate NFT count
  if (nfts.length !== EXPECTED_TOTAL_NFTS) {
    console.warn(`⚠ WARNING: Expected ${EXPECTED_TOTAL_NFTS} NFTs but found ${nfts.length}`);
    console.log("Continuing anyway...\n");
  }

  // Calculate expected multiplier points
  let calculatedPoints = 0;
  const hostessCounts = {};
  for (const nft of nfts) {
    const multiplier = getMultiplier(nft.hostess_index);
    calculatedPoints += multiplier;
    hostessCounts[nft.hostess_index] = (hostessCounts[nft.hostess_index] || 0) + 1;
  }

  console.log("NFT Distribution by Hostess:");
  console.log("─".repeat(50));
  const hostessNames = [
    "Penelope Fatale", "Mia Siren", "Cleo Enchante", "Sophia Spark",
    "Luna Mirage", "Aurora Seductra", "Scarlett Ember", "Vivienne Allure"
  ];
  for (let i = 0; i < 8; i++) {
    const count = hostessCounts[i] || 0;
    const multiplier = getMultiplier(i);
    console.log(`  ${i}: ${hostessNames[i].padEnd(20)} = ${count.toString().padStart(4)} NFTs × ${multiplier}x = ${(count * multiplier).toString().padStart(6)} pts`);
  }
  console.log("─".repeat(50));
  console.log(`  Total: ${nfts.length} NFTs, ${calculatedPoints} multiplier points\n`);

  if (calculatedPoints !== EXPECTED_TOTAL_MULTIPLIER_POINTS) {
    console.warn(`⚠ WARNING: Expected ${EXPECTED_TOTAL_MULTIPLIER_POINTS} points but calculated ${calculatedPoints}`);
  }

  // Connect to contract using compiled artifact (more reliable than minimal ABI)
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE\n");

  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const nftRewarder = NFTRewarder.attach(NFT_REWARDER_ADDRESS).connect(deployer);

  // Check admin
  const admin = await nftRewarder.admin();
  console.log("NFTRewarder admin:", admin);
  console.log("Deployer is admin:", admin.toLowerCase() === deployer.address.toLowerCase() ? "✓ Yes" : "✗ No");

  if (admin.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error("\n✗ ERROR: Deployer is not the admin. Cannot register NFTs.");
    process.exit(1);
  }

  // Check current state
  const currentTotal = await nftRewarder.totalRegisteredNFTs();
  const currentPoints = await nftRewarder.totalMultiplierPoints();
  console.log(`\nCurrent state: ${currentTotal} NFTs registered, ${currentPoints} multiplier points`);

  if (currentTotal > 0) {
    console.log("\n⚠ WARNING: NFTs are already registered!");
    console.log("This script will skip already-registered NFTs.\n");
  }

  // Filter out already registered NFTs (check first one in each batch)
  console.log("\nChecking for already registered NFTs...");
  const unregisteredNFTs = [];

  for (const nft of nfts) {
    const metadata = await nftRewarder.nftMetadata(nft.token_id);
    if (!metadata.registered) {
      unregisteredNFTs.push(nft);
    }
  }

  console.log(`✓ ${unregisteredNFTs.length} NFTs need to be registered\n`);

  if (unregisteredNFTs.length === 0) {
    console.log("All NFTs are already registered. Nothing to do.\n");

    // Verify final state
    const finalTotal = await nftRewarder.totalRegisteredNFTs();
    const finalPoints = await nftRewarder.totalMultiplierPoints();
    console.log("=== Final State ===");
    console.log(`Total registered NFTs: ${finalTotal}`);
    console.log(`Total multiplier points: ${finalPoints}`);

    db.close();
    return;
  }

  // Register NFTs in batches
  console.log(`Registering ${unregisteredNFTs.length} NFTs in batches of ${BATCH_SIZE}...\n`);

  const batches = [];
  for (let i = 0; i < unregisteredNFTs.length; i += BATCH_SIZE) {
    batches.push(unregisteredNFTs.slice(i, i + BATCH_SIZE));
  }

  let totalRegistered = 0;
  for (let i = 0; i < batches.length; i++) {
    const batch = batches[i];

    const tokenIds = batch.map(n => n.token_id);
    const owners = batch.map(n => ethers.getAddress(n.owner));  // Fix checksum
    const hostessIndices = batch.map(n => n.hostess_index);

    console.log(`Batch ${i + 1}/${batches.length}: Registering ${batch.length} NFTs (tokens ${tokenIds[0]} to ${tokenIds[tokenIds.length - 1]})...`);

    try {
      const tx = await nftRewarder.batchRegisterNFTs(tokenIds, hostessIndices, owners, {
        gasLimit: 3000000  // ~100k gas per NFT, 25 NFTs = 2.5M gas max
      });
      console.log(`  TX: ${tx.hash}`);

      const receipt = await tx.wait();
      console.log(`  ✓ Confirmed in block ${receipt.blockNumber} (gas used: ${receipt.gasUsed.toString()})`);

      totalRegistered += batch.length;
    } catch (error) {
      console.error(`  ✗ Failed:`, error.message);
      if (error.data) {
        console.error(`  Error data:`, error.data);
      }
      console.log("  Continuing with next batch...\n");
    }
  }

  console.log(`\n✓ Registration complete. ${totalRegistered} NFTs registered.\n`);

  // Verify final state
  const finalTotal = await nftRewarder.totalRegisteredNFTs();
  const finalPoints = await nftRewarder.totalMultiplierPoints();

  console.log("=== Final State ===");
  console.log(`Total registered NFTs: ${finalTotal} (expected: ${EXPECTED_TOTAL_NFTS})`);
  console.log(`Total multiplier points: ${finalPoints} (expected: ${EXPECTED_TOTAL_MULTIPLIER_POINTS})`);

  if (Number(finalTotal) === EXPECTED_TOTAL_NFTS && Number(finalPoints) === EXPECTED_TOTAL_MULTIPLIER_POINTS) {
    console.log("\n✅ SUCCESS: All NFTs registered correctly!");
  } else {
    console.log("\n⚠ WARNING: Final totals don't match expected values. Please verify manually.");
  }

  // Spot check a few NFTs
  console.log("\n=== Spot Check ===");
  const spotCheckIds = [1, 100, 500, 1000, 2000];
  for (const tokenId of spotCheckIds) {
    const nft = nfts.find(n => n.token_id === tokenId);
    if (nft) {
      const metadata = await nftRewarder.nftMetadata(tokenId);
      const dbOwner = nft.owner.toLowerCase();
      const contractOwner = metadata.owner.toLowerCase();
      const ownerMatch = dbOwner === contractOwner;
      console.log(`  Token #${tokenId}: hostess=${metadata.hostessIndex}, registered=${metadata.registered}, owner match=${ownerMatch ? "✓" : "✗"}`);
      if (!ownerMatch) {
        console.log(`    DB owner: ${dbOwner}`);
        console.log(`    Contract owner: ${contractOwner}`);
      }
    }
  }

  db.close();
  console.log("\n✓ Done!");
}

/**
 * Get multiplier for a hostess index (matches contract)
 */
function getMultiplier(hostessIndex) {
  const multipliers = [100, 90, 80, 70, 60, 50, 40, 30];
  return multipliers[hostessIndex] || 0;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
