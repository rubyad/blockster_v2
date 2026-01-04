// Script to recalculate hostess counts from the sales table
// Run this on production after CSV import or if counts are wrong

const Database = require('better-sqlite3');
const path = require('path');

// Production uses /data, local uses ./data
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data', 'highrollers.db');

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

console.log(`Using database: ${DB_PATH}`);

const db = new Database(DB_PATH);

// Get current counts
console.log('\nCurrent hostess counts (from hostess_counts table):');
const currentCounts = db.prepare('SELECT hostess_index, count FROM hostess_counts ORDER BY hostess_index').all();
let currentTotal = 0;
currentCounts.forEach(row => {
  console.log(`  ${HOSTESS_MAP[row.hostess_index]}: ${row.count}`);
  currentTotal += row.count;
});
console.log(`  Total: ${currentTotal}`);

// Get actual counts from sales
console.log('\nActual counts from sales table:');
const salesCounts = db.prepare(`
  SELECT hostess_index, COUNT(*) as count FROM sales GROUP BY hostess_index ORDER BY hostess_index
`).all();
let salesTotal = 0;
salesCounts.forEach(row => {
  console.log(`  ${HOSTESS_MAP[row.hostess_index]}: ${row.count}`);
  salesTotal += row.count;
});
console.log(`  Total: ${salesTotal}`);

// Update hostess_counts from sales
console.log('\nUpdating hostess_counts table...');
db.prepare('UPDATE hostess_counts SET count = 0').run();

const updateStmt = db.prepare('UPDATE hostess_counts SET count = ? WHERE hostess_index = ?');
salesCounts.forEach(row => {
  updateStmt.run(row.count, row.hostess_index);
});

// Verify
console.log('\nUpdated hostess counts:');
const newCounts = db.prepare('SELECT hostess_index, count FROM hostess_counts ORDER BY hostess_index').all();
let newTotal = 0;
newCounts.forEach(row => {
  console.log(`  ${HOSTESS_MAP[row.hostess_index]}: ${row.count}`);
  newTotal += row.count;
});
console.log(`  Total: ${newTotal}`);

db.close();
console.log('\nDone!');
