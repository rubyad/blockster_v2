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

    // Create indexes
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_nfts_owner ON nfts(owner);
      CREATE INDEX IF NOT EXISTS idx_nfts_hostess ON nfts(hostess_index);
      CREATE INDEX IF NOT EXISTS idx_nfts_last_sync ON nfts(last_owner_sync);
      CREATE INDEX IF NOT EXISTS idx_sales_timestamp ON sales(timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_sales_buyer ON sales(buyer);
      CREATE INDEX IF NOT EXISTS idx_affiliate_earnings_affiliate ON affiliate_earnings(affiliate);
      CREATE INDEX IF NOT EXISTS idx_affiliate_earnings_tier ON affiliate_earnings(tier);
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

  // Affiliate Operations
  insertAffiliateEarning(data) {
    const stmt = this.db.prepare(`
      INSERT INTO affiliate_earnings (token_id, tier, affiliate, earnings, tx_hash)
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
      ORDER BY ae.timestamp DESC
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
      SELECT ae.*, n.hostess_name, n.hostess_index
      FROM affiliate_earnings ae
      LEFT JOIN nfts n ON ae.token_id = n.token_id
      ORDER BY ae.timestamp DESC
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

  // Utility
  close() {
    this.db.close();
  }
}

module.exports = DatabaseService;
