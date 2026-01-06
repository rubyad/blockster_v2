/**
 * Check if any NFT hostess indices don't match between DB and contract
 */

const { ethers } = require("hardhat");
const Database = require('better-sqlite3');
const path = require('path');

const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
const DB_PATH = path.resolve(__dirname, "../../../high-rollers-nfts/data/highrollers.db");

async function main() {
  console.log("=== Checking Hostess Index Mismatches ===\n");

  // Connect to contract
  const [deployer] = await ethers.getSigners();
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const nftRewarder = NFTRewarder.attach(NFT_REWARDER_ADDRESS).connect(deployer);

  // Connect to database
  const db = new Database(DB_PATH, { readonly: true });

  // Get all NFTs from database
  const dbNFTs = db.prepare(`
    SELECT token_id, owner, hostess_index
    FROM nfts
    ORDER BY token_id ASC
  `).all();

  console.log(`Checking ${dbNFTs.length} NFTs...\n`);

  const mismatches = [];
  const multipliers = [100, 90, 80, 70, 60, 50, 40, 30];
  let onChainPoints = 0;
  let dbPoints = 0;

  // Check in batches to avoid RPC rate limits
  const BATCH_SIZE = 50;
  for (let i = 0; i < dbNFTs.length; i += BATCH_SIZE) {
    const batch = dbNFTs.slice(i, i + BATCH_SIZE);
    process.stdout.write(`\rChecking ${i + batch.length}/${dbNFTs.length}...`);

    for (const nft of batch) {
      const metadata = await nftRewarder.nftMetadata(nft.token_id);
      const contractHostess = Number(metadata.hostessIndex);
      const dbHostess = nft.hostess_index;

      onChainPoints += multipliers[contractHostess];
      dbPoints += multipliers[dbHostess];

      if (contractHostess !== dbHostess) {
        mismatches.push({
          tokenId: nft.token_id,
          dbHostess,
          contractHostess,
          dbMult: multipliers[dbHostess],
          contractMult: multipliers[contractHostess],
          pointsDiff: multipliers[dbHostess] - multipliers[contractHostess]
        });
      }
    }
  }

  console.log(`\n\nOn-chain calculated points: ${onChainPoints}`);
  console.log(`Database calculated points: ${dbPoints}`);
  console.log(`Difference: ${dbPoints - onChainPoints}\n`);

  if (mismatches.length > 0) {
    console.log(`Found ${mismatches.length} mismatches:\n`);
    let totalPointsDiff = 0;

    for (const m of mismatches) {
      totalPointsDiff += m.pointsDiff;
      console.log(`  Token #${m.tokenId}: DB hostess=${m.dbHostess} (${m.dbMult}x), Contract hostess=${m.contractHostess} (${m.contractMult}x), diff=${m.pointsDiff}`);
    }

    console.log(`\nTotal points difference from mismatches: ${totalPointsDiff}`);
  } else {
    console.log("All hostess indices match!");
  }

  db.close();
}

main().catch(console.error);
