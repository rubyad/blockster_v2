#!/usr/bin/env node
/**
 * Sync Time Rewards Script
 *
 * Syncs existing special NFTs (2340+) from the NFTRewarder contract
 * to the local database for time reward tracking.
 *
 * Usage:
 *   node server/scripts/sync-time-rewards.js
 *   node server/scripts/sync-time-rewards.js --token 2340
 *   node server/scripts/sync-time-rewards.js --range 2340-2345
 *   node server/scripts/sync-time-rewards.js --pool-only
 */

require('dotenv').config();

const { ethers } = require('ethers');
const path = require('path');

// Load config and database
const config = require('../config');
const DatabaseService = require('../services/database');

// Constants
const SPECIAL_NFT_START = 2340;
const SPECIAL_NFT_END = 2700;

// ABI for time reward functions
const NFT_REWARDER_ABI = [
  'function getTimeRewardInfo(uint256 tokenId) view returns (uint256 startTime, uint256 endTime, uint256 pending, uint256 claimed, uint256 ratePerSecond, uint256 timeRemaining, uint256 totalFor180Days, bool isActive)',
  'function getTimeRewardPoolStats() view returns (uint256 deposited, uint256 remaining, uint256 claimed, uint256 specialNFTs)',
  'function nftMetadata(uint256 tokenId) view returns (uint8 hostessIndex, bool registered, address owner)',
  'function totalRegisteredNFTs() view returns (uint256)'
];

async function main() {
  const args = process.argv.slice(2);

  // Parse arguments
  let tokenId = null;
  let rangeStart = null;
  let rangeEnd = null;
  let poolOnly = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--token' && args[i + 1]) {
      tokenId = parseInt(args[i + 1]);
      i++;
    } else if (args[i] === '--range' && args[i + 1]) {
      const parts = args[i + 1].split('-');
      rangeStart = parseInt(parts[0]);
      rangeEnd = parseInt(parts[1]) || rangeStart;
      i++;
    } else if (args[i] === '--pool-only') {
      poolOnly = true;
    }
  }

  console.log('[SyncTimeRewards] Starting...');
  console.log(`[SyncTimeRewards] NFTRewarder: ${config.NFT_REWARDER_ADDRESS}`);
  console.log(`[SyncTimeRewards] RPC: ${config.ROGUE_RPC_URL}`);

  // Initialize provider and contract
  const provider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
  const contract = new ethers.Contract(
    config.NFT_REWARDER_ADDRESS,
    NFT_REWARDER_ABI,
    provider
  );

  // Initialize database
  const db = new DatabaseService();

  try {
    // Always sync pool stats first
    console.log('\n[SyncTimeRewards] Syncing pool stats...');
    const [deposited, remaining, claimed, specialNFTs] = await contract.getTimeRewardPoolStats();

    db.updateTimeRewardGlobalStats({
      poolDeposited: ethers.formatEther(deposited),
      poolRemaining: ethers.formatEther(remaining),
      poolClaimed: ethers.formatEther(claimed),
      nftsStarted: Number(specialNFTs)
    });

    console.log(`[SyncTimeRewards] Pool Stats:`);
    console.log(`  - Deposited: ${ethers.formatEther(deposited)} ROGUE`);
    console.log(`  - Remaining: ${ethers.formatEther(remaining)} ROGUE`);
    console.log(`  - Claimed: ${ethers.formatEther(claimed)} ROGUE`);
    console.log(`  - Special NFTs: ${specialNFTs}`);

    if (poolOnly) {
      console.log('\n[SyncTimeRewards] Pool-only mode, skipping NFT sync.');
      db.close();
      return;
    }

    // Determine which NFTs to sync
    let nftsToSync = [];

    if (tokenId !== null) {
      nftsToSync = [tokenId];
      console.log(`\n[SyncTimeRewards] Syncing single NFT: ${tokenId}`);
    } else if (rangeStart !== null) {
      for (let i = rangeStart; i <= rangeEnd; i++) {
        nftsToSync.push(i);
      }
      console.log(`\n[SyncTimeRewards] Syncing range: ${rangeStart}-${rangeEnd} (${nftsToSync.length} NFTs)`);
    } else {
      // Default: sync all special NFTs that exist
      const totalSupply = await contract.totalRegisteredNFTs();
      console.log(`\n[SyncTimeRewards] Total registered NFTs: ${totalSupply}`);

      // Check which special NFTs are registered
      for (let i = SPECIAL_NFT_START; i <= Math.min(SPECIAL_NFT_END, Number(totalSupply)); i++) {
        nftsToSync.push(i);
      }
      console.log(`[SyncTimeRewards] Checking special NFTs: ${SPECIAL_NFT_START}-${Math.min(SPECIAL_NFT_END, Number(totalSupply))}`);
    }

    // Sync each NFT
    let synced = 0;
    let skipped = 0;

    for (const id of nftsToSync) {
      try {
        // Get time reward info
        const [startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive] =
          await contract.getTimeRewardInfo(id);

        if (startTime === 0n) {
          // Not a special NFT or not started
          skipped++;
          continue;
        }

        // Get metadata for hostess index and owner
        const [hostessIndex, registered, owner] = await contract.nftMetadata(id);

        if (!registered) {
          skipped++;
          continue;
        }

        // Calculate last claim time from pending and rate
        // pending and ratePerSecond are both in wei, so division gives seconds
        // elapsedSinceClaim = pending / ratePerSecond
        // lastClaimTime = now - elapsedSinceClaim
        const pendingWei = Number(pending);
        const rateWei = Number(ratePerSecond);
        const elapsedSinceClaim = rateWei > 0 ? pendingWei / rateWei : 0;
        const now = Math.floor(Date.now() / 1000);
        const calculatedLastClaimTime = Math.floor(now - elapsedSinceClaim);

        // Ensure lastClaimTime is not before startTime (can happen due to timing)
        const lastClaimTime = Math.max(calculatedLastClaimTime, Number(startTime));
        const claimedNum = Number(claimed) / 1e18;

        // Insert into database
        db.insertTimeRewardNFT({
          tokenId: id,
          hostessIndex: Number(hostessIndex),
          owner,
          startTime: Number(startTime),
          lastClaimTime,
          totalEarned: 0,  // Let real-time calculation handle this
          totalClaimed: claimedNum
        });

        synced++;

        console.log(`[SyncTimeRewards] NFT #${id}:`);
        console.log(`  - Hostess: ${hostessIndex}`);
        console.log(`  - Owner: ${owner}`);
        console.log(`  - Start Time: ${new Date(Number(startTime) * 1000).toISOString()}`);
        console.log(`  - Pending: ${ethers.formatEther(pending)} ROGUE`);
        console.log(`  - Claimed: ${ethers.formatEther(claimed)} ROGUE`);
        console.log(`  - Rate: ${ethers.formatEther(ratePerSecond)} ROGUE/sec`);
        console.log(`  - Time Remaining: ${Number(timeRemaining) / 86400} days`);
        console.log(`  - Active: ${isActive}`);

      } catch (error) {
        console.error(`[SyncTimeRewards] Error syncing NFT #${id}:`, error.message);
        skipped++;
      }

      // Small delay to avoid rate limiting
      await new Promise(r => setTimeout(r, 100));
    }

    console.log(`\n[SyncTimeRewards] Complete!`);
    console.log(`  - Synced: ${synced}`);
    console.log(`  - Skipped: ${skipped}`);

  } catch (error) {
    console.error('[SyncTimeRewards] Fatal error:', error);
    process.exit(1);
  } finally {
    db.close();
  }
}

main();
