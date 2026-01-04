const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const DB_PATH = path.join(__dirname, 'data', 'highrollers.db');
const NFT_CSV = path.join(__dirname, '..', 'high_rollers_nfts_production.csv');
const AFFILIATE_CSV = path.join(__dirname, '..', 'high_rollers_affiliate_payouts_production.csv');

// Hostess mapping from girl_type to index
const HOSTESS_MAP = {
  0: { name: 'Penelope Fatale', index: 0 },
  1: { name: 'Mia Siren', index: 1 },
  2: { name: 'Cleo Enchante', index: 2 },
  3: { name: 'Sophia Spark', index: 3 },
  4: { name: 'Luna Mirage', index: 4 },
  5: { name: 'Aurora Seductra', index: 5 },
  6: { name: 'Scarlett Ember', index: 6 },
  7: { name: 'Vivienne Allure', index: 7 }
};

function parseCSV(content) {
  const lines = content.trim().split('\n');
  const headers = lines[0].split(',').map(h => h.trim());
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',').map(v => v.trim());
    const row = {};
    headers.forEach((h, idx) => {
      row[h] = values[idx];
    });
    rows.push(row);
  }

  return rows;
}

async function importData() {
  const db = new Database(DB_PATH);

  // Clear existing sales and affiliate_earnings
  console.log('Clearing existing sales and affiliate_earnings...');
  db.exec('DELETE FROM sales');
  db.exec('DELETE FROM affiliate_earnings');

  // Read CSV files
  console.log('Reading CSV files...');
  const nftData = parseCSV(fs.readFileSync(NFT_CSV, 'utf8'));
  const affiliateData = parseCSV(fs.readFileSync(AFFILIATE_CSV, 'utf8'));

  console.log(`Found ${nftData.length} NFTs and ${affiliateData.length} affiliate payouts`);

  // Import sales from NFT CSV
  const insertSale = db.prepare(`
    INSERT INTO sales (token_id, buyer, hostess_index, hostess_name, price, tx_hash, block_number, timestamp, affiliate, affiliate2)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  console.log('Importing sales...');
  let salesImported = 0;

  for (const row of nftData) {
    const tokenId = parseInt(row.id);
    const price = row.price.trim();
    const buyer = row.buyer;
    const girlType = parseInt(row.girl_type);
    const hostess = HOSTESS_MAP[girlType] || { name: 'Unknown', index: girlType };
    const mintedAt = parseInt(row.minted_at) / 1000000; // Convert from microseconds to seconds
    const affiliate1 = row.affiliate_1 && row.affiliate_1 !== '' ? row.affiliate_1 : null;
    const affiliate2 = row.affiliate_2 && row.affiliate_2 !== '' ? row.affiliate_2 : null;

    // Generate synthetic tx hash based on token ID
    const txHash = `0x${tokenId.toString(16).padStart(64, '0')}`;

    try {
      insertSale.run(
        tokenId,
        buyer.toLowerCase(),
        hostess.index,
        hostess.name,
        price,
        txHash,
        0,
        Math.floor(mintedAt),
        affiliate1?.toLowerCase() || null,
        affiliate2?.toLowerCase() || null
      );
      salesImported++;
    } catch (err) {
      console.error(`Error inserting sale for token ${tokenId}:`, err.message);
    }
  }

  console.log(`Imported ${salesImported} sales`);

  // Import affiliate earnings
  const insertAffiliateEarning = db.prepare(`
    INSERT INTO affiliate_earnings (token_id, tier, affiliate, earnings, tx_hash, timestamp)
    VALUES (?, ?, ?, ?, ?, ?)
  `);

  console.log('Importing affiliate earnings...');
  let affiliateImported = 0;

  for (const row of affiliateData) {
    const tokenId = parseInt(row.token_id);
    const tier = parseInt(row.tier);
    const affiliate = row.affiliate;
    const payout = row.payout.trim();
    const paidAt = parseInt(row.paid_at) / 1000000; // Convert from microseconds to seconds

    // Generate synthetic tx hash
    const txHash = `0x${tokenId.toString(16).padStart(64, '0')}`;

    try {
      insertAffiliateEarning.run(
        tokenId,
        tier,
        affiliate.toLowerCase(),
        payout,
        txHash,
        Math.floor(paidAt)
      );
      affiliateImported++;
    } catch (err) {
      console.error(`Error inserting affiliate earning for token ${tokenId}:`, err.message);
    }
  }

  console.log(`Imported ${affiliateImported} affiliate earnings`);

  // Verify
  const salesCount = db.prepare('SELECT COUNT(*) as count FROM sales').get();
  const affiliateCount = db.prepare('SELECT COUNT(*) as count FROM affiliate_earnings').get();

  console.log('\nFinal counts:');
  console.log(`  Sales: ${salesCount.count}`);
  console.log(`  Affiliate earnings: ${affiliateCount.count}`);

  db.close();
}

importData().catch(console.error);
