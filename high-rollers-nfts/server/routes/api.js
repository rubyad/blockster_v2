const express = require('express');
const { ethers } = require('ethers');
const config = require('../config');

module.exports = (db, contractService, ownerSync) => {
  const router = express.Router();

  // Get collection stats
  router.get('/stats', async (req, res) => {
    try {
      const stats = await contractService.getCollectionStats();

      // Calculate hostess counts from nfts table (ground truth - synced from Arbitrum contract)
      const nftCounts = db.db.prepare(`
        SELECT hostess_index, COUNT(*) as count FROM nfts GROUP BY hostess_index
      `).all();

      const hostessCounts = {};
      nftCounts.forEach(row => {
        hostessCounts[row.hostess_index] = row.count;
      });

      res.json({
        ...stats,
        hostessCounts,
        hostesses: config.HOSTESSES.map(h => ({
          ...h,
          count: hostessCounts[h.index] || 0
        }))
      });
    } catch (error) {
      console.error('[API] /stats error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get all hostesses with counts
  router.get('/hostesses', (req, res) => {
    try {
      // Calculate counts from nfts table (ground truth - synced from Arbitrum contract)
      const nftCounts = db.db.prepare(`
        SELECT hostess_index, COUNT(*) as count FROM nfts GROUP BY hostess_index
      `).all();

      const hostessCounts = {};
      nftCounts.forEach(row => {
        hostessCounts[row.hostess_index] = row.count;
      });

      const hostesses = config.HOSTESSES.map(h => ({
        ...h,
        count: hostessCounts[h.index] || 0
      }));

      res.json(hostesses);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get recent sales
  router.get('/sales', (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 50, 100);
      const offset = parseInt(req.query.offset) || 0;

      const sales = db.getSales(limit, offset);

      // Enrich with hostess data
      const enrichedSales = sales.map(sale => ({
        ...sale,
        hostessRarity: config.HOSTESSES[sale.hostess_index]?.rarity,
        hostessMultiplier: config.HOSTESSES[sale.hostess_index]?.multiplier,
        hostessImage: config.HOSTESSES[sale.hostess_index]?.image,
        priceETH: ethers.formatEther(sale.price)
      }));

      res.json(enrichedSales);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get NFTs by owner
  router.get('/nfts/:owner', async (req, res) => {
    try {
      const { owner } = req.params;

      if (!ethers.isAddress(owner)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      // First check database
      let nfts = db.getNFTsByOwner(owner);

      // If empty, try syncing from contract
      if (nfts.length === 0) {
        await ownerSync.syncWalletNFTs(owner);
        nfts = db.getNFTsByOwner(owner);
      }

      // Enrich with hostess data
      const enrichedNFTs = nfts.map(nft => ({
        ...nft,
        hostessRarity: config.HOSTESSES[nft.hostess_index]?.rarity,
        hostessMultiplier: config.HOSTESSES[nft.hostess_index]?.multiplier,
        hostessImage: config.HOSTESSES[nft.hostess_index]?.image,
        hostessDescription: config.HOSTESSES[nft.hostess_index]?.description
      }));

      res.json(enrichedNFTs);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get single NFT details
  router.get('/nft/:tokenId', async (req, res) => {
    try {
      const tokenId = parseInt(req.params.tokenId);

      if (isNaN(tokenId) || tokenId < 1) {
        return res.status(400).json({ error: 'Invalid token ID' });
      }

      let nft = db.getNFT(tokenId);

      // If not in database, try fetching from contract
      if (!nft) {
        const details = await contractService.getNFTDetails(tokenId);
        if (details) {
          db.insertNFT({
            tokenId: details.tokenId,
            owner: details.owner,
            hostessIndex: details.hostessIndex,
            hostessName: details.hostessName
          });
          nft = db.getNFT(tokenId);
        }
      }

      if (!nft) {
        return res.status(404).json({ error: 'NFT not found' });
      }

      res.json({
        ...nft,
        hostessRarity: config.HOSTESSES[nft.hostess_index]?.rarity,
        hostessMultiplier: config.HOSTESSES[nft.hostess_index]?.multiplier,
        hostessImage: config.HOSTESSES[nft.hostess_index]?.image,
        hostessDescription: config.HOSTESSES[nft.hostess_index]?.description
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get affiliate stats for an address
  router.get('/affiliates/:address', async (req, res) => {
    try {
      const { address } = req.params;

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      // Get from database
      const dbStats = db.getAffiliateStats(address);

      // Also try to get balance from contract
      try {
        const contractInfo = await contractService.getAffiliateInfo(address);
        dbStats.tier1.balance = contractInfo.balance;
      } catch (e) {
        // Contract call failed, use database info
      }

      res.json(dbStats);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get all affiliate earnings (for public leaderboard)
  router.get('/affiliates', (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 100, 500);
      const offset = parseInt(req.query.offset) || 0;

      const earnings = db.getAllAffiliateEarnings(limit, offset);

      // Enrich with formatted amounts
      const enrichedEarnings = earnings.map(e => ({
        ...e,
        earningsETH: ethers.formatEther(e.earnings),
        hostessImage: config.HOSTESSES[e.hostess_index]?.image
      }));

      res.json(enrichedEarnings);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Record affiliate withdrawal
  router.post('/affiliates/withdrawal', (req, res) => {
    try {
      const { address, txHash } = req.body;

      if (!address || !txHash) {
        return res.status(400).json({ error: 'Missing address or txHash' });
      }

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      // Record the withdrawal
      db.recordWithdrawal({
        address: address.toLowerCase(),
        txHash,
        timestamp: Math.floor(Date.now() / 1000)
      });

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get buyer info from contract
  router.get('/buyer/:address', async (req, res) => {
    try {
      const { address } = req.params;

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      const buyerInfo = await contractService.getBuyerInfo(address);
      res.json(buyerInfo);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Check if minting is available
  router.get('/mint-status', async (req, res) => {
    try {
      const totalSupply = await contractService.getTotalSupply();
      const minted = Number(totalSupply);
      const remaining = config.APP_MAX_SUPPLY - minted;
      const soldOut = minted >= config.APP_MAX_SUPPLY;

      res.json({
        minted,
        remaining: Math.max(0, remaining),
        maxSupply: config.APP_MAX_SUPPLY,
        soldOut,
        price: config.MINT_PRICE,
        priceETH: config.MINT_PRICE_ETH
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Link buyer to affiliate (permanent association)
  // This calls the smart contract using the affiliateLinker wallet
  router.post('/link-affiliate', async (req, res) => {
    try {
      const { buyer, affiliate } = req.body;

      if (!buyer || !affiliate) {
        return res.status(400).json({ error: 'Missing buyer or affiliate address' });
      }

      if (!ethers.isAddress(buyer) || !ethers.isAddress(affiliate)) {
        return res.status(400).json({ error: 'Invalid address format' });
      }

      // Check if buyer already has an affiliate in our database
      const existingAffiliate = db.getBuyerAffiliate(buyer);
      if (existingAffiliate) {
        // Return the existing affiliate - first referrer always wins
        return res.json({
          success: true,
          affiliate: existingAffiliate,
          isNew: false,
          onChain: false
        });
      }

      // Link buyer to affiliate on-chain using the affiliateLinker wallet
      // Retry up to 3 times to handle nonce conflicts from concurrent requests
      let onChainSuccess = false;
      if (config.AFFILIATE_LINKER_PRIVATE_KEY) {
        const provider = new ethers.JsonRpcProvider(config.RPC_URL);
        const affiliateLinkerWallet = new ethers.Wallet(config.AFFILIATE_LINKER_PRIVATE_KEY, provider);
        const contract = new ethers.Contract(config.CONTRACT_ADDRESS, config.CONTRACT_ABI, affiliateLinkerWallet);

        for (let attempt = 1; attempt <= 3; attempt++) {
          try {
            console.log(`[API] Linking affiliate on-chain (attempt ${attempt}): buyer=${buyer}, affiliate=${affiliate}`);
            const tx = await contract.linkAffiliate(buyer, affiliate);
            await tx.wait();
            console.log(`[API] On-chain affiliate link successful: tx=${tx.hash}`);
            onChainSuccess = true;
            break;
          } catch (onChainError) {
            const isNonceError = onChainError.message?.toLowerCase().includes('nonce') ||
                                 onChainError.message?.toLowerCase().includes('replacement');

            if (isNonceError && attempt < 3) {
              console.log(`[API] Nonce conflict, retrying in 2 seconds... (attempt ${attempt}/3)`);
              await new Promise(r => setTimeout(r, 2000));
              continue;
            }

            // Log but don't fail - still save to database
            console.error('[API] On-chain affiliate link failed:', onChainError.message);
            break;
          }
        }
      } else {
        console.warn('[API] AFFILIATE_LINKER_PRIVATE_KEY not set - skipping on-chain link');
      }

      // Link buyer to new affiliate in database
      db.linkBuyerToAffiliate(buyer, affiliate);

      res.json({
        success: true,
        affiliate: affiliate.toLowerCase(),
        isNew: true,
        onChain: onChainSuccess
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get buyer's linked affiliate
  router.get('/buyer-affiliate/:buyer', (req, res) => {
    try {
      const { buyer } = req.params;

      if (!ethers.isAddress(buyer)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      const affiliate = db.getBuyerAffiliate(buyer);

      res.json({
        buyer: buyer.toLowerCase(),
        affiliate: affiliate || config.DEFAULT_AFFILIATE,
        hasCustomAffiliate: !!affiliate
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Import sales data from CSV (admin endpoint)
  router.post('/import-sales-csv', express.text({ type: '*/*', limit: '10mb' }), (req, res) => {
    try {
      const csvContent = req.body;
      if (!csvContent || typeof csvContent !== 'string') {
        return res.status(400).json({ error: 'No CSV content provided' });
      }

      const lines = csvContent.trim().split('\n');
      const headers = lines[0].split(',').map(h => h.trim());

      // Hostess mapping
      const HOSTESS_MAP = {
        0: 'Penelope Fatale',
        1: 'Mia Siren',
        2: 'Cleo Enchante',
        3: 'Sophia Spark',
        4: 'Luna Mirage',
        5: 'Aurora Seductra',
        6: 'Scarlett Ember',
        7: 'Vivienne Allure'
      };

      let imported = 0;
      let skipped = 0;

      for (let i = 1; i < lines.length; i++) {
        const values = lines[i].split(',').map(v => v.trim());
        const row = {};
        headers.forEach((h, idx) => {
          row[h] = values[idx];
        });

        const tokenId = parseInt(row.id);
        const txHash = `0x${tokenId.toString(16).padStart(64, '0')}`;

        // Skip if already exists
        if (db.saleExists(txHash)) {
          skipped++;
          continue;
        }

        const girlType = parseInt(row.girl_type);
        const hostessName = HOSTESS_MAP[girlType] || 'Unknown';
        const mintedAt = parseInt(row.minted_at) / 1000000; // microseconds to seconds

        db.insertSale({
          tokenId,
          buyer: row.buyer.toLowerCase(),
          hostessIndex: girlType,
          hostessName,
          price: row.price.trim(),
          txHash,
          blockNumber: 0,
          timestamp: Math.floor(mintedAt),
          affiliate: row.affiliate_1 && row.affiliate_1 !== '' ? row.affiliate_1.toLowerCase() : null,
          affiliate2: row.affiliate_2 && row.affiliate_2 !== '' ? row.affiliate_2.toLowerCase() : null
        });
        imported++;
      }

      console.log(`[API] Imported ${imported} sales, skipped ${skipped} existing`);
      res.json({ success: true, imported, skipped, total: lines.length - 1 });
    } catch (error) {
      console.error('[API] Import CSV error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Import affiliate earnings data from CSV (admin endpoint)
  router.post('/import-affiliates-csv', express.text({ type: '*/*', limit: '10mb' }), (req, res) => {
    try {
      const csvContent = req.body;
      if (!csvContent || typeof csvContent !== 'string') {
        return res.status(400).json({ error: 'No CSV content provided' });
      }

      const lines = csvContent.trim().split('\n');
      const headers = lines[0].split(',').map(h => h.trim());

      let imported = 0;
      let skipped = 0;

      for (let i = 1; i < lines.length; i++) {
        const values = lines[i].split(',').map(v => v.trim());
        const row = {};
        headers.forEach((h, idx) => {
          row[h] = values[idx];
        });

        const tokenId = parseInt(row.token_id);
        const tier = parseInt(row.tier);
        const affiliate = row.affiliate;
        const payout = row.payout.trim();
        const paidAt = parseInt(row.paid_at) / 1000000; // microseconds to seconds
        const txHash = `0x${tokenId.toString(16).padStart(64, '0')}`;

        try {
          db.insertAffiliateEarning({
            tokenId,
            tier,
            affiliate: affiliate.toLowerCase(),
            earnings: payout,
            txHash
          });
          imported++;
        } catch (err) {
          // Skip duplicates
          skipped++;
        }
      }

      console.log(`[API] Imported ${imported} affiliate earnings, skipped ${skipped}`);
      res.json({ success: true, imported, skipped, total: lines.length - 1 });
    } catch (error) {
      console.error('[API] Import affiliates CSV error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Health check
  router.get('/health', async (req, res) => {
    try {
      const blockNumber = await contractService.getBlockNumber();
      res.json({
        status: 'ok',
        blockNumber,
        dbNFTs: db.getTotalNFTs()
      });
    } catch (error) {
      res.status(500).json({ status: 'error', error: error.message });
    }
  });

  // Recalculate hostess counts from database
  router.post('/recalculate-counts', (req, res) => {
    try {
      const counts = db.recalculateHostessCounts();
      res.json({ success: true, counts });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Generate sales from existing NFTs (fallback when event sync doesn't work)
  router.post('/generate-sales-from-nfts', (req, res) => {
    try {
      const allNFTs = db.db.prepare('SELECT * FROM nfts ORDER BY token_id ASC').all();
      const existingSales = db.db.prepare('SELECT token_id FROM sales').all();
      const existingTokenIds = new Set(existingSales.map(s => s.token_id));

      let salesGenerated = 0;
      let affiliateEarningsGenerated = 0;

      // Calculate timestamp spread - assume minting happened over time
      const now = Math.floor(Date.now() / 1000);
      const startTime = now - (30 * 24 * 60 * 60); // 30 days ago
      const timePerToken = (now - startTime) / allNFTs.length;

      for (let i = 0; i < allNFTs.length; i++) {
        const nft = allNFTs[i];

        // Skip if sale already exists
        if (existingTokenIds.has(nft.token_id)) continue;

        // Generate synthetic tx hash since we don't have the real one
        const syntheticTxHash = `0x${nft.token_id.toString().padStart(64, '0')}`;

        // Generate timestamp based on token ID order
        const timestamp = Math.floor(startTime + (i * timePerToken));

        const price = nft.mint_price || config.MINT_PRICE;
        const hostessData = config.HOSTESSES[nft.hostess_index];

        // Insert sale
        db.insertSale({
          tokenId: nft.token_id,
          buyer: nft.owner,
          hostessIndex: nft.hostess_index,
          hostessName: hostessData?.name || 'Unknown',
          price: price,
          txHash: syntheticTxHash,
          blockNumber: 0,
          timestamp: timestamp,
          affiliate: nft.affiliate,
          affiliate2: nft.affiliate2
        });
        salesGenerated++;

        // Generate affiliate earnings if present
        if (nft.affiliate && nft.affiliate !== ethers.ZeroAddress) {
          const tier1Earnings = (BigInt(price) / 5n).toString(); // 20%
          db.insertAffiliateEarning({
            tokenId: nft.token_id,
            tier: 1,
            affiliate: nft.affiliate,
            earnings: tier1Earnings,
            txHash: syntheticTxHash
          });
          affiliateEarningsGenerated++;
        }

        if (nft.affiliate2 && nft.affiliate2 !== ethers.ZeroAddress) {
          const tier2Earnings = (BigInt(price) / 20n).toString(); // 5%
          db.insertAffiliateEarning({
            tokenId: nft.token_id,
            tier: 2,
            affiliate: nft.affiliate2,
            earnings: tier2Earnings,
            txHash: syntheticTxHash
          });
          affiliateEarningsGenerated++;
        }
      }

      console.log(`[API] Generated ${salesGenerated} sales, ${affiliateEarningsGenerated} affiliate earnings from NFTs`);

      res.json({
        success: true,
        salesGenerated,
        affiliateEarningsGenerated,
        totalNFTs: allNFTs.length,
        alreadyExisted: existingTokenIds.size
      });
    } catch (error) {
      console.error('[API] Generate sales error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Sync historical events (sales and affiliate earnings)
  router.post('/sync-historical-events', async (req, res) => {
    try {
      const provider = new ethers.JsonRpcProvider(config.RPC_URL);
      const contract = new ethers.Contract(config.CONTRACT_ADDRESS, config.CONTRACT_ABI, provider);

      // Contract was deployed around block 280000000 on Arbitrum
      const currentBlock = await provider.getBlockNumber();
      const startBlock = 280000000; // Approximate contract deployment
      const chunkSize = 9999; // RPC limits to 10,000 blocks

      let totalSynced = 0;
      let totalAffiliateEarnings = 0;

      console.log(`[API] Starting historical sync from block ${startBlock} to ${currentBlock}`);

      // Collect all events first, then batch get timestamps
      const allEvents = [];

      // Query events in chunks
      for (let fromBlock = startBlock; fromBlock <= currentBlock; fromBlock += chunkSize) {
        const toBlock = Math.min(fromBlock + chunkSize - 1, currentBlock);

        try {
          const filter = contract.filters.NFTMinted();
          const events = await contract.queryFilter(filter, fromBlock, toBlock);

          for (const event of events) {
            // Skip if sale already exists
            if (db.saleExists(event.transactionHash)) continue;
            allEvents.push(event);
          }

          if (events.length > 0) {
            console.log(`[API] Found ${events.length} events in blocks ${fromBlock}-${toBlock}`);
          }
        } catch (chunkError) {
          console.error(`[API] Error syncing blocks ${fromBlock}-${toBlock}:`, chunkError.message);
        }

        // Rate limiting - 500ms delay between chunks to stay under 100/sec
        await new Promise(resolve => setTimeout(resolve, 500));
      }

      console.log(`[API] Found ${allEvents.length} new events to sync`);

      // Now process events with timestamps in batches
      for (let i = 0; i < allEvents.length; i++) {
        const event = allEvents[i];
        const [, recipient, price, tokenId, hostess, affiliate, affiliate2] = event.args;
        const txHash = event.transactionHash;
        const blockNumber = event.blockNumber;

        // Get block timestamp with rate limiting
        let timestamp;
        try {
          const block = await provider.getBlock(blockNumber);
          timestamp = block ? Number(block.timestamp) : Math.floor(Date.now() / 1000);
        } catch {
          timestamp = Math.floor(Date.now() / 1000);
        }

        const hostessIndex = Number(hostess);
        const hostessData = config.HOSTESSES[hostessIndex];
        const hostessName = hostessData?.name || 'Unknown';
        const priceStr = price.toString();

        // Calculate affiliate earnings
        const tier1Earnings = (BigInt(priceStr) / 5n).toString(); // 20%
        const tier2Earnings = (BigInt(priceStr) / 20n).toString(); // 5%

        // Store sale
        db.insertSale({
          tokenId: Number(tokenId),
          buyer: recipient,
          hostessIndex,
          hostessName,
          price: priceStr,
          txHash,
          blockNumber,
          timestamp,
          affiliate,
          affiliate2
        });
        totalSynced++;

        // Record affiliate earnings
        if (affiliate && affiliate !== ethers.ZeroAddress) {
          db.insertAffiliateEarning({
            tokenId: Number(tokenId),
            tier: 1,
            affiliate,
            earnings: tier1Earnings,
            txHash
          });
          totalAffiliateEarnings++;
        }

        if (affiliate2 && affiliate2 !== ethers.ZeroAddress) {
          db.insertAffiliateEarning({
            tokenId: Number(tokenId),
            tier: 2,
            affiliate: affiliate2,
            earnings: tier2Earnings,
            txHash
          });
          totalAffiliateEarnings++;
        }

        // Rate limit block fetches
        if (i % 10 === 0) {
          await new Promise(resolve => setTimeout(resolve, 200));
        }

        if ((i + 1) % 100 === 0) {
          console.log(`[API] Processed ${i + 1}/${allEvents.length} events`);
        }
      }

      console.log(`[API] Historical sync complete: ${totalSynced} sales, ${totalAffiliateEarnings} affiliate earnings`);

      res.json({
        success: true,
        salesSynced: totalSynced,
        affiliateEarningsSynced: totalAffiliateEarnings
      });
    } catch (error) {
      console.error('[API] Historical sync error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  return router;
};
