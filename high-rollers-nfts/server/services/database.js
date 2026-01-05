const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');
const config = require('../config');

class DatabaseService {
  constructor(dbPath = config.DB_PATH) {
    // Ensure data directory exists
    const dir = path.dirname(dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    this.db = new Database(dbPath);
    this.db.pragma('journal_mode = WAL');
    this.initSchema();
  }

  initSchema() {
    // NFTs table - stores all minted NFTs
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS nfts (
        token_id INTEGER PRIMARY KEY,
        owner TEXT NOT NULL,
        hostess_index INTEGER NOT NULL,
        hostess_name TEXT NOT NULL,
        mint_price TEXT,
        mint_tx_hash TEXT,
        affiliate TEXT,
        affiliate2 TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        last_owner_sync INTEGER DEFAULT 0
      )
    `);

    // Sales table - records all mint transactions
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token_id INTEGER NOT NULL,
        buyer TEXT NOT NULL,
        hostess_index INTEGER NOT NULL,
        hostess_name TEXT NOT NULL,
        price TEXT NOT NULL,
        tx_hash TEXT UNIQUE NOT NULL,
        block_number INTEGER,
        timestamp INTEGER NOT NULL,
        affiliate TEXT,
        affiliate2 TEXT,
        FOREIGN KEY (token_id) REFERENCES nfts(token_id)
      )
    `);

    // Affiliate earnings table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS affiliate_earnings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token_id INTEGER NOT NULL,
        tier INTEGER NOT NULL,
        affiliate TEXT NOT NULL,
        earnings TEXT NOT NULL,
        tx_hash TEXT NOT NULL,
        timestamp INTEGER DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (token_id) REFERENCES nfts(token_id)
      )
    `);

    // Withdrawals table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        amount TEXT,
        tx_hash TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL
      )
    `);

    // Hostess counts cache table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS hostess_counts (
        hostess_index INTEGER PRIMARY KEY,
        count INTEGER DEFAULT 0
      )
    `);

    // Initialize hostess counts if empty
    const countExists = this.db.prepare('SELECT COUNT(*) as c FROM hostess_counts').get();
    if (countExists.c === 0) {
      const insert = this.db.prepare('INSERT INTO hostess_counts (hostess_index, count) VALUES (?, 0)');
      for (let i = 0; i < 8; i++) {
        insert.run(i);
      }
    }

    // Pending mints table (for tracking VRF callbacks)
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS pending_mints (
        request_id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        token_id TEXT,
        price TEXT NOT NULL,
        tx_hash TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    `);

    // Buyer-affiliate links table (permanent association)
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS buyer_affiliates (
        buyer TEXT PRIMARY KEY,
        affiliate TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    `);

    // NFT earnings table - tracks revenue sharing earnings per NFT
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS nft_earnings (
        token_id INTEGER PRIMARY KEY,
        total_earned TEXT DEFAULT '0',
        pending_amount TEXT DEFAULT '0',
        last_24h_earned TEXT DEFAULT '0',
        apy_basis_points INTEGER DEFAULT 0,
        last_synced INTEGER DEFAULT 0,
        FOREIGN KEY (token_id) REFERENCES nfts(token_id)
      )
    `);

    // Reward events table - records each RewardReceived event from NFTRewarder
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS reward_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        commitment_hash TEXT NOT NULL,
        amount TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        block_number INTEGER NOT NULL,
        tx_hash TEXT UNIQUE NOT NULL
      )
    `);

    // Reward withdrawals table - records RewardClaimed events
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS reward_withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_address TEXT NOT NULL,
        amount TEXT NOT NULL,
        token_ids TEXT NOT NULL,
        tx_hash TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL
      )
    `);

    // Global revenue stats cache
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS global_revenue_stats (
        id INTEGER PRIMARY KEY DEFAULT 1,
        total_rewards_received TEXT DEFAULT '0',
        total_rewards_distributed TEXT DEFAULT '0',
        rewards_last_24h TEXT DEFAULT '0',
        overall_apy_basis_points INTEGER DEFAULT 0,
        last_updated INTEGER DEFAULT 0
      )
    `);

    // Initialize global revenue stats if empty
    const statsExist = this.db.prepare('SELECT COUNT(*) as c FROM global_revenue_stats').get();
    if (statsExist.c === 0) {
      this.db.prepare('INSERT INTO global_revenue_stats (id) VALUES (1)').run();
    }

    // Per-hostess revenue stats cache
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS hostess_revenue_stats (
        hostess_index INTEGER PRIMARY KEY,
        nft_count INTEGER DEFAULT 0,
        total_points INTEGER DEFAULT 0,
        share_basis_points INTEGER DEFAULT 0,
        last_24h_per_nft TEXT DEFAULT '0',
        apy_basis_points INTEGER DEFAULT 0,
        last_updated INTEGER DEFAULT 0
      )
    `);

    // Initialize hostess revenue stats if empty
    const hostessStatsExist = this.db.prepare('SELECT COUNT(*) as c FROM hostess_revenue_stats').get();
    if (hostessStatsExist.c === 0) {
      const insertHostessStats = this.db.prepare('INSERT INTO hostess_revenue_stats (hostess_index) VALUES (?)');
      for (let i = 0; i < 8; i++) {
        insertHostessStats.run(i);
      }
    }

    // Create indexes
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_nfts_owner ON nfts(owner);
      CREATE INDEX IF NOT EXISTS idx_nfts_hostess ON nfts(hostess_index);
      CREATE INDEX IF NOT EXISTS idx_nfts_last_sync ON nfts(last_owner_sync);
      CREATE INDEX IF NOT EXISTS idx_sales_timestamp ON sales(timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_sales_buyer ON sales(buyer);
      CREATE INDEX IF NOT EXISTS idx_affiliate_earnings_affiliate ON affiliate_earnings(affiliate);
      CREATE INDEX IF NOT EXISTS idx_affiliate_earnings_tier ON affiliate_earnings(tier);
      CREATE INDEX IF NOT EXISTS idx_reward_events_timestamp ON reward_events(timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_reward_withdrawals_user ON reward_withdrawals(user_address);
      CREATE INDEX IF NOT EXISTS idx_nft_earnings_pending ON nft_earnings(pending_amount);
    `);

    console.log('[Database] Schema initialized');
  }

  // NFT Operations
  insertNFT(data) {
    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO nfts (token_id, owner, hostess_index, hostess_name, mint_price, mint_tx_hash, affiliate, affiliate2, last_owner_sync)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
    `);
    return stmt.run(
      data.tokenId,
      data.owner.toLowerCase(),
      data.hostessIndex,
      data.hostessName,
      data.mintPrice,
      data.mintTxHash,
      data.affiliate?.toLowerCase(),
      data.affiliate2?.toLowerCase()
    );
  }

  upsertNFT(data) {
    const existing = this.getNFT(data.tokenId);
    if (existing) {
      return this.updateNFTOwner(data.tokenId, data.owner);
    }
    return this.insertNFT(data);
  }

  getNFT(tokenId) {
    return this.db.prepare('SELECT * FROM nfts WHERE token_id = ?').get(tokenId);
  }

  nftExists(tokenId) {
    const result = this.db.prepare('SELECT 1 FROM nfts WHERE token_id = ?').get(tokenId);
    return !!result;
  }

  updateNFTOwner(tokenId, owner) {
    const stmt = this.db.prepare(`
      UPDATE nfts SET owner = ?, last_owner_sync = strftime('%s', 'now')
      WHERE token_id = ?
    `);
    return stmt.run(owner.toLowerCase(), tokenId);
  }

  getNFTsByOwner(owner) {
    return this.db.prepare(`
      SELECT * FROM nfts WHERE owner = ? ORDER BY token_id ASC
    `).all(owner.toLowerCase());
  }

  getAllNFTs(limit = 100, offset = 0) {
    return this.db.prepare(`
      SELECT * FROM nfts ORDER BY token_id DESC LIMIT ? OFFSET ?
    `).all(limit, offset);
  }

  getTotalNFTs() {
    const result = this.db.prepare('SELECT COUNT(*) as count FROM nfts').get();
    return result.count;
  }

  // Sales Operations
  insertSale(data) {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO sales (token_id, buyer, hostess_index, hostess_name, price, tx_hash, block_number, timestamp, affiliate, affiliate2)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    return stmt.run(
      data.tokenId,
      data.buyer.toLowerCase(),
      data.hostessIndex,
      data.hostessName,
      data.price,
      data.txHash,
      data.blockNumber,
      data.timestamp,
      data.affiliate?.toLowerCase(),
      data.affiliate2?.toLowerCase()
    );
  }

  getSales(limit = 50, offset = 0) {
    return this.db.prepare(`
      SELECT * FROM sales ORDER BY timestamp DESC LIMIT ? OFFSET ?
    `).all(limit, offset);
  }

  getSalesByBuyer(buyer, limit = 50) {
    return this.db.prepare(`
      SELECT * FROM sales WHERE buyer = ? ORDER BY timestamp DESC LIMIT ?
    `).all(buyer.toLowerCase(), limit);
  }

  saleExists(txHash) {
    const result = this.db.prepare('SELECT 1 FROM sales WHERE tx_hash = ?').get(txHash);
    return !!result;
  }

  saleExistsForToken(tokenId) {
    const result = this.db.prepare('SELECT 1 FROM sales WHERE token_id = ?').get(tokenId);
    return !!result;
  }

  /**
   * Upsert sale - if sale exists with fake tx_hash (from OwnerSync), update it with real data
   * This ensures EventListener's real tx_hash takes priority over OwnerSync's fake hash
   */
  upsertSale(data) {
    const existing = this.db.prepare('SELECT tx_hash FROM sales WHERE token_id = ?').get(data.tokenId);

    if (existing) {
      // If existing record has a fake tx_hash (from OwnerSync), update it with real data
      if (existing.tx_hash && existing.tx_hash.startsWith('sync_owner_')) {
        const updateStmt = this.db.prepare(`
          UPDATE sales
          SET tx_hash = ?, block_number = ?, affiliate = ?, affiliate2 = ?
          WHERE token_id = ?
        `);
        console.log(`[DB] Updating sale for token ${data.tokenId} with real tx_hash`);
        return updateStmt.run(
          data.txHash,
          data.blockNumber,
          data.affiliate?.toLowerCase(),
          data.affiliate2?.toLowerCase(),
          data.tokenId
        );
      }
      // Otherwise, sale already exists with real data, skip
      console.log(`[DB] Sale for token ${data.tokenId} already exists with real tx_hash, skipping`);
      return { changes: 0 };
    }

    // No existing sale, insert new
    return this.insertSale(data);
  }

  // Hostess Counts
  incrementHostessCount(hostessIndex) {
    const stmt = this.db.prepare(`
      UPDATE hostess_counts SET count = count + 1 WHERE hostess_index = ?
    `);
    return stmt.run(hostessIndex);
  }

  getHostessCount(hostessIndex) {
    const result = this.db.prepare('SELECT count FROM hostess_counts WHERE hostess_index = ?').get(hostessIndex);
    return result?.count || 0;
  }

  getAllHostessCounts() {
    const rows = this.db.prepare('SELECT hostess_index, count FROM hostess_counts ORDER BY hostess_index').all();
    const counts = {};
    rows.forEach(row => {
      counts[row.hostess_index] = row.count;
    });
    return counts;
  }

  setHostessCount(hostessIndex, count) {
    const stmt = this.db.prepare(`
      UPDATE hostess_counts SET count = ? WHERE hostess_index = ?
    `);
    return stmt.run(count, hostessIndex);
  }

  recalculateHostessCounts() {
    const counts = this.db.prepare(`
      SELECT hostess_index, COUNT(*) as count FROM nfts GROUP BY hostess_index
    `).all();

    // Reset all to 0 first
    this.db.prepare('UPDATE hostess_counts SET count = 0').run();

    // Set actual counts
    const stmt = this.db.prepare('UPDATE hostess_counts SET count = ? WHERE hostess_index = ?');
    counts.forEach(row => {
      stmt.run(row.count, row.hostess_index);
    });

    return this.getAllHostessCounts();
  }

  // Recalculate hostess counts from sales table (more reliable than nfts for imported data)
  recalculateHostessCountsFromSales() {
    const counts = this.db.prepare(`
      SELECT hostess_index, COUNT(*) as count FROM sales GROUP BY hostess_index
    `).all();

    // Reset all to 0 first
    this.db.prepare('UPDATE hostess_counts SET count = 0').run();

    // Set actual counts
    const stmt = this.db.prepare('UPDATE hostess_counts SET count = ? WHERE hostess_index = ?');
    counts.forEach(row => {
      stmt.run(row.count, row.hostess_index);
    });

    console.log('[Database] Recalculated hostess counts from sales table');
    return this.getAllHostessCounts();
  }

  // Affiliate Operations
  insertAffiliateEarning(data) {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO affiliate_earnings (token_id, tier, affiliate, earnings, tx_hash)
      VALUES (?, ?, ?, ?, ?)
    `);
    return stmt.run(
      data.tokenId,
      data.tier,
      data.affiliate.toLowerCase(),
      data.earnings,
      data.txHash
    );
  }

  getAffiliateEarnings(affiliate) {
    return this.db.prepare(`
      SELECT * FROM affiliate_earnings WHERE affiliate = ? ORDER BY timestamp DESC
    `).all(affiliate.toLowerCase());
  }

  getAffiliateStats(affiliate) {
    const addr = affiliate.toLowerCase();

    // Tier 1 stats
    const tier1 = this.db.prepare(`
      SELECT COUNT(*) as count, COALESCE(SUM(CAST(earnings AS REAL)), 0) as total
      FROM affiliate_earnings WHERE affiliate = ? AND tier = 1
    `).get(addr);

    // Tier 2 stats
    const tier2 = this.db.prepare(`
      SELECT COUNT(*) as count, COALESCE(SUM(CAST(earnings AS REAL)), 0) as total
      FROM affiliate_earnings WHERE affiliate = ? AND tier = 2
    `).get(addr);

    // Per-NFT earnings
    const earningsPerNFT = this.db.prepare(`
      SELECT ae.token_id, ae.tier, ae.earnings, ae.tx_hash, s.buyer as buyer_address
      FROM affiliate_earnings ae
      LEFT JOIN sales s ON ae.token_id = s.token_id
      WHERE ae.affiliate = ?
      ORDER BY s.timestamp DESC, ae.token_id DESC
    `).all(addr);

    return {
      tier1: {
        count: tier1.count,
        earnings: tier1.total.toString(),
        balance: '0' // Would need to query contract for actual balance
      },
      tier2: {
        count: tier2.count,
        earnings: tier2.total.toString()
      },
      earningsPerNFT
    };
  }

  getAllAffiliateEarnings(limit = 100, offset = 0) {
    return this.db.prepare(`
      SELECT ae.*, s.hostess_name, s.hostess_index, s.timestamp as sale_timestamp
      FROM affiliate_earnings ae
      LEFT JOIN sales s ON ae.token_id = s.token_id
      ORDER BY s.timestamp DESC, ae.token_id DESC
      LIMIT ? OFFSET ?
    `).all(limit, offset);
  }

  // Withdrawal Operations
  recordWithdrawal(data) {
    const stmt = this.db.prepare(`
      INSERT INTO withdrawals (address, amount, tx_hash, timestamp)
      VALUES (?, ?, ?, ?)
    `);
    return stmt.run(
      data.address.toLowerCase(),
      data.amount,
      data.txHash,
      data.timestamp
    );
  }

  getWithdrawals(address) {
    return this.db.prepare(`
      SELECT * FROM withdrawals WHERE address = ? ORDER BY timestamp DESC
    `).all(address.toLowerCase());
  }

  // Pending Mints Operations
  insertPendingMint(data) {
    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO pending_mints (request_id, sender, token_id, price, tx_hash)
      VALUES (?, ?, ?, ?, ?)
    `);
    return stmt.run(data.requestId, data.sender.toLowerCase(), data.tokenId, data.price, data.txHash);
  }

  getPendingMint(requestId) {
    return this.db.prepare('SELECT * FROM pending_mints WHERE request_id = ?').get(requestId);
  }

  deletePendingMint(requestId) {
    return this.db.prepare('DELETE FROM pending_mints WHERE request_id = ?').run(requestId);
  }

  getOldPendingMints(maxAgeSeconds = 300) {
    const cutoff = Math.floor(Date.now() / 1000) - maxAgeSeconds;
    return this.db.prepare(`
      SELECT * FROM pending_mints WHERE created_at < ?
    `).all(cutoff);
  }

  // Buyer-Affiliate Link Operations
  linkBuyerToAffiliate(buyer, affiliate) {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO buyer_affiliates (buyer, affiliate)
      VALUES (?, ?)
    `);
    return stmt.run(buyer.toLowerCase(), affiliate.toLowerCase());
  }

  getBuyerAffiliate(buyer) {
    const result = this.db.prepare(
      'SELECT affiliate FROM buyer_affiliates WHERE buyer = ?'
    ).get(buyer.toLowerCase());
    return result?.affiliate || null;
  }

  hasBuyerAffiliate(buyer) {
    const result = this.db.prepare(
      'SELECT 1 FROM buyer_affiliates WHERE buyer = ?'
    ).get(buyer.toLowerCase());
    return !!result;
  }

  // ==========================================
  // NFT Revenue Sharing Operations
  // ==========================================

  /**
   * Get total rewards received since a specific timestamp
   * Used to calculate global 24h rewards for proportional distribution
   * @param {number} sinceTimestamp - Unix timestamp (seconds)
   * @returns {string} Total rewards in wei
   */
  getRewardsSince(sinceTimestamp) {
    // Sum amounts as BigInt in JS to avoid SQLite integer overflow
    // (wei amounts can exceed SQLite's 2^63 limit)
    const rows = this.db.prepare(`
      SELECT amount FROM reward_events WHERE timestamp >= ?
    `).all(sinceTimestamp);

    let total = 0n;
    for (const row of rows) {
      total += BigInt(row.amount || '0');
    }
    return total.toString();
  }

  /**
   * Insert a new reward event (called by RewardEventListener when RewardReceived emitted)
   */
  insertRewardEvent(data) {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO reward_events (commitment_hash, amount, timestamp, block_number, tx_hash)
      VALUES (?, ?, ?, ?, ?)
    `);
    return stmt.run(
      data.commitmentHash,
      data.amount,
      data.timestamp,
      data.blockNumber,
      data.txHash
    );
  }

  /**
   * Get recent reward events for display
   */
  getRewardEvents(limit = 50, offset = 0) {
    return this.db.prepare(`
      SELECT * FROM reward_events ORDER BY timestamp DESC LIMIT ? OFFSET ?
    `).all(limit, offset);
  }

  /**
   * Get total reward events count
   */
  getRewardEventsCount() {
    const result = this.db.prepare('SELECT COUNT(*) as count FROM reward_events').get();
    return result.count;
  }

  /**
   * Update NFT earnings (called by EarningsSyncService)
   */
  updateNFTEarnings(tokenId, data) {
    const stmt = this.db.prepare(`
      INSERT INTO nft_earnings (token_id, total_earned, pending_amount, last_24h_earned, apy_basis_points, last_synced)
      VALUES (?, ?, ?, ?, ?, strftime('%s', 'now'))
      ON CONFLICT(token_id) DO UPDATE SET
        total_earned = excluded.total_earned,
        pending_amount = excluded.pending_amount,
        last_24h_earned = excluded.last_24h_earned,
        apy_basis_points = excluded.apy_basis_points,
        last_synced = strftime('%s', 'now')
    `);
    return stmt.run(
      tokenId,
      data.totalEarned,
      data.pendingAmount,
      data.last24hEarned,
      data.apyBasisPoints
    );
  }

  /**
   * Bulk update last_24h_earned and apy_basis_points for all NFTs of a hostess type
   * Used when global 24h changes mid-sync
   */
  updateNFTLast24hByHostess(hostessIndex, last24hEarned, apyBasisPoints) {
    const stmt = this.db.prepare(`
      UPDATE nft_earnings
      SET last_24h_earned = ?, apy_basis_points = ?, last_synced = strftime('%s', 'now')
      WHERE token_id IN (SELECT token_id FROM nfts WHERE hostess_index = ?)
    `);
    return stmt.run(last24hEarned, apyBasisPoints, hostessIndex);
  }

  /**
   * Get earnings for a specific NFT
   */
  getNFTEarnings(tokenId) {
    return this.db.prepare(`
      SELECT ne.*, n.owner, n.hostess_index, n.hostess_name
      FROM nft_earnings ne
      JOIN nfts n ON ne.token_id = n.token_id
      WHERE ne.token_id = ?
    `).get(tokenId);
  }

  /**
   * Get earnings for all NFTs owned by a specific address
   */
  getNFTEarningsByOwner(owner) {
    return this.db.prepare(`
      SELECT ne.*, n.owner, n.hostess_index, n.hostess_name
      FROM nfts n
      LEFT JOIN nft_earnings ne ON n.token_id = ne.token_id
      WHERE n.owner = ?
      ORDER BY n.token_id ASC
    `).all(owner.toLowerCase());
  }

  /**
   * Get all NFT earnings with owner info (for batch sync)
   */
  getAllNFTEarnings() {
    return this.db.prepare(`
      SELECT n.token_id, n.owner, n.hostess_index, n.hostess_name,
             COALESCE(ne.total_earned, '0') as total_earned,
             COALESCE(ne.pending_amount, '0') as pending_amount,
             COALESCE(ne.last_24h_earned, '0') as last_24h_earned,
             COALESCE(ne.apy_basis_points, 0) as apy_basis_points,
             ne.last_synced
      FROM nfts n
      LEFT JOIN nft_earnings ne ON n.token_id = ne.token_id
      ORDER BY n.token_id ASC
    `).all();
  }

  /**
   * Record a reward withdrawal (RewardClaimed event)
   */
  recordRewardWithdrawal(data) {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO reward_withdrawals (user_address, amount, token_ids, tx_hash, timestamp)
      VALUES (?, ?, ?, ?, ?)
    `);
    return stmt.run(
      data.userAddress.toLowerCase(),
      data.amount,
      data.tokenIds,  // JSON string array
      data.txHash,
      data.timestamp
    );
  }

  /**
   * Get withdrawals for a specific user
   */
  getRewardWithdrawals(userAddress, limit = 50) {
    return this.db.prepare(`
      SELECT * FROM reward_withdrawals
      WHERE user_address = ?
      ORDER BY timestamp DESC
      LIMIT ?
    `).all(userAddress.toLowerCase(), limit);
  }

  /**
   * Reset pending amount to 0 for a specific NFT (after claim)
   */
  resetNFTPending(tokenId) {
    const stmt = this.db.prepare(`
      UPDATE nft_earnings SET pending_amount = '0', last_synced = strftime('%s', 'now')
      WHERE token_id = ?
    `);
    return stmt.run(tokenId);
  }

  /**
   * Get global revenue stats
   */
  getGlobalRevenueStats() {
    return this.db.prepare('SELECT * FROM global_revenue_stats WHERE id = 1').get();
  }

  /**
   * Update global revenue stats
   */
  updateGlobalRevenueStats(data) {
    const stmt = this.db.prepare(`
      UPDATE global_revenue_stats SET
        total_rewards_received = ?,
        total_rewards_distributed = ?,
        rewards_last_24h = ?,
        overall_apy_basis_points = ?,
        last_updated = strftime('%s', 'now')
      WHERE id = 1
    `);
    return stmt.run(
      data.totalRewardsReceived,
      data.totalRewardsDistributed,
      data.rewardsLast24h,
      data.overallAPY
    );
  }

  /**
   * Get all hostess revenue stats
   */
  getAllHostessRevenueStats() {
    return this.db.prepare(`
      SELECT * FROM hostess_revenue_stats ORDER BY hostess_index
    `).all();
  }

  /**
   * Update hostess revenue stats
   */
  updateHostessRevenueStats(hostessIndex, data) {
    const stmt = this.db.prepare(`
      UPDATE hostess_revenue_stats SET
        nft_count = ?,
        total_points = ?,
        share_basis_points = ?,
        last_24h_per_nft = ?,
        apy_basis_points = ?,
        last_updated = strftime('%s', 'now')
      WHERE hostess_index = ?
    `);
    return stmt.run(
      data.nftCount,
      data.totalPoints,
      data.shareBasisPoints,
      data.last24hPerNft,
      data.apyBasisPoints,
      hostessIndex
    );
  }

  /**
   * Get total multiplier points across all registered NFTs
   */
  getTotalMultiplierPoints() {
    const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];
    const result = this.db.prepare(`
      SELECT hostess_index, COUNT(*) as count FROM nfts GROUP BY hostess_index
    `).all();

    let total = 0;
    result.forEach(row => {
      total += row.count * MULTIPLIERS[row.hostess_index];
    });
    return total;
  }

  /**
   * Recalculate and update all hostess revenue stats
   */
  recalculateHostessRevenueStats() {
    const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];
    const totalPoints = this.getTotalMultiplierPoints();

    const counts = this.db.prepare(`
      SELECT hostess_index, COUNT(*) as count FROM nfts GROUP BY hostess_index
    `).all();

    const stmt = this.db.prepare(`
      UPDATE hostess_revenue_stats SET
        nft_count = ?,
        total_points = ?,
        share_basis_points = ?,
        last_updated = strftime('%s', 'now')
      WHERE hostess_index = ?
    `);

    // Reset all to 0
    for (let i = 0; i < 8; i++) {
      stmt.run(0, 0, 0, i);
    }

    // Update actual values
    counts.forEach(row => {
      const multiplier = MULTIPLIERS[row.hostess_index];
      const points = row.count * multiplier;
      const shareBp = totalPoints > 0 ? Math.round((points / totalPoints) * 10000) : 0;
      stmt.run(row.count, points, shareBp, row.hostess_index);
    });

    console.log('[Database] Recalculated hostess revenue stats');
    return this.getAllHostessRevenueStats();
  }

  // Utility
  close() {
    this.db.close();
  }
}


module.exports = DatabaseService;
