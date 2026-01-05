// One-time script to clean up duplicate sale for token 2341
// Run with: node cleanup-duplicate-2341.js

const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data', 'highrollers.db');

console.log('Using database:', DB_PATH);

const db = new Database(DB_PATH);

// Check current state
console.log('\nCurrent sales for token 2341:');
const sales = db.prepare('SELECT id, token_id, tx_hash, buyer FROM sales WHERE token_id = 2341').all();
sales.forEach(s => {
  console.log(`  id=${s.id}, tx_hash=${s.tx_hash.substring(0, 20)}...`);
});

if (sales.length <= 1) {
  console.log('\nNo duplicates found. Nothing to clean up.');
  db.close();
  process.exit(0);
}

// Find and delete entries with fake tx_hash (starts with 0x000)
let deleted = 0;
for (const sale of sales) {
  if (sale.tx_hash.startsWith('0x000')) {
    console.log(`\nDeleting fake entry id=${sale.id} with tx_hash=${sale.tx_hash.substring(0, 20)}...`);
    db.prepare('DELETE FROM sales WHERE id = ?').run(sale.id);
    deleted++;
  }
}

// Also check affiliate_earnings for duplicates
console.log('\nChecking affiliate_earnings for token 2341:');
const earnings = db.prepare('SELECT id, token_id, tier, tx_hash FROM affiliate_earnings WHERE token_id = 2341').all();
earnings.forEach(e => {
  console.log(`  id=${e.id}, tier=${e.tier}, tx_hash=${e.tx_hash.substring(0, 20)}...`);
});

// Delete duplicate affiliate earnings with fake tx_hash
const seenTiers = new Set();
let deletedEarnings = 0;
for (const e of earnings) {
  if (seenTiers.has(e.tier)) {
    if (e.tx_hash.startsWith('0x000')) {
      console.log(`\nDeleting duplicate affiliate earning id=${e.id}, tier=${e.tier}`);
      db.prepare('DELETE FROM affiliate_earnings WHERE id = ?').run(e.id);
      deletedEarnings++;
    }
  }
  seenTiers.add(e.tier);
}

console.log(`\nCleanup complete: ${deleted} sales deleted, ${deletedEarnings} affiliate earnings deleted`);

// Verify
console.log('\nRemaining sales for token 2341:');
const remaining = db.prepare('SELECT id, token_id, tx_hash FROM sales WHERE token_id = 2341').all();
remaining.forEach(s => {
  console.log(`  id=${s.id}, tx_hash=${s.tx_hash.substring(0, 20)}...`);
});

db.close();
