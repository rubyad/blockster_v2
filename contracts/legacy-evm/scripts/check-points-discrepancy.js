/**
 * Investigate the 60-point discrepancy in multiplier points
 * Expected: 109390, Actual: 109330, Difference: 60
 *
 * 60 points could be:
 * - 2 NFTs with multiplier 30 (Vivienne) missing
 * - 1 NFT with multiplier 60 (Luna) missing
 * - Or some combination
 */

const { ethers } = require("hardhat");
const Database = require('better-sqlite3');
const path = require('path');

const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
const DB_PATH = path.resolve(__dirname, "../../../high-rollers-nfts/data/highrollers.db");

async function main() {
  console.log("=== Investigating Multiplier Points Discrepancy ===\n");
  console.log("Expected: 109390");
  console.log("Actual:   109330");
  console.log("Missing:  60 points\n");

  // Connect to contract
  const [deployer] = await ethers.getSigners();
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const nftRewarder = NFTRewarder.attach(NFT_REWARDER_ADDRESS).connect(deployer);

  // Get on-chain totals
  const totalRegistered = await nftRewarder.totalRegisteredNFTs();
  const totalPoints = await nftRewarder.totalMultiplierPoints();
  console.log(`On-chain: ${totalRegistered} NFTs, ${totalPoints} points\n`);

  // Connect to database
  const db = new Database(DB_PATH, { readonly: true });

  // Get all NFTs from database
  const dbNFTs = db.prepare(`
    SELECT token_id, owner, hostess_index
    FROM nfts
    ORDER BY token_id ASC
  `).all();

  console.log(`Database: ${dbNFTs.length} NFTs\n`);

  // Check each NFT in database against contract
  console.log("Checking for unregistered NFTs...\n");
  const unregistered = [];

  for (const nft of dbNFTs) {
    const metadata = await nftRewarder.nftMetadata(nft.token_id);
    if (!metadata.registered) {
      unregistered.push(nft);
    }
  }

  if (unregistered.length > 0) {
    console.log(`Found ${unregistered.length} unregistered NFTs:\n`);
    const multipliers = [100, 90, 80, 70, 60, 50, 40, 30];
    let missingPoints = 0;

    for (const nft of unregistered) {
      const mult = multipliers[nft.hostess_index];
      missingPoints += mult;
      console.log(`  Token #${nft.token_id}: hostess=${nft.hostess_index}, multiplier=${mult}`);
    }

    console.log(`\nTotal missing points: ${missingPoints}`);
  } else {
    console.log("All NFTs are registered!");
  }

  // Also verify database vs contract totals
  console.log("\n=== Database Calculation ===");
  const multipliers = [100, 90, 80, 70, 60, 50, 40, 30];
  const hostessCounts = {};
  let calculatedPoints = 0;

  for (const nft of dbNFTs) {
    const mult = multipliers[nft.hostess_index];
    calculatedPoints += mult;
    hostessCounts[nft.hostess_index] = (hostessCounts[nft.hostess_index] || 0) + 1;
  }

  console.log("NFT Distribution:");
  const hostessNames = [
    "Penelope Fatale", "Mia Siren", "Cleo Enchante", "Sophia Spark",
    "Luna Mirage", "Aurora Seductra", "Scarlett Ember", "Vivienne Allure"
  ];
  for (let i = 0; i < 8; i++) {
    const count = hostessCounts[i] || 0;
    const mult = multipliers[i];
    console.log(`  ${i}: ${hostessNames[i].padEnd(20)} = ${count.toString().padStart(4)} NFTs × ${mult}x = ${(count * mult).toString().padStart(6)} pts`);
  }
  console.log(`\nCalculated total: ${calculatedPoints} points`);

  db.close();
}

main().catch(console.error);
