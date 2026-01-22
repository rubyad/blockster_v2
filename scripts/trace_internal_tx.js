/**
 * Trace a specific internal transaction to understand where tournament winnings come from
 */

const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const TOURNAMENT_CONTRACT = '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058';
const EXPLORER_API = 'https://roguescan.io/api/v2';

async function main() {
  // Get internal transactions for the wallet
  const response = await fetch(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/internal-transactions`);
  const data = await response.json();

  console.log('=== SAMPLE INTERNAL TRANSACTIONS ===');
  console.log('');

  // Look at first few internal txs from tournament
  const tournamentTxs = data.items.filter(tx =>
    tx.from?.hash?.toLowerCase() === TOURNAMENT_CONTRACT.toLowerCase()
  );

  console.log(`Found ${tournamentTxs.length} internal txs from tournament in first page`);
  console.log('');

  // Show details of first few
  for (let i = 0; i < Math.min(5, tournamentTxs.length); i++) {
    const tx = tournamentTxs[i];
    console.log(`=== Transaction ${i + 1} ===`);
    console.log('TX Hash:', tx.transaction_hash);
    console.log('From:', tx.from?.hash);
    console.log('To:', tx.to?.hash);
    console.log('Value:', ethers.formatEther(tx.value || '0'), 'ROGUE');
    console.log('Block:', tx.block_number);
    console.log('Timestamp:', tx.timestamp);
    console.log('Type:', tx.type);
    console.log('URL:', `https://roguescan.io/tx/${tx.transaction_hash}`);
    console.log('');
  }

  // Now let's look at the FULL internal tx list to see all sources
  console.log('=== ALL SOURCES IN FIRST PAGE ===');
  const bySource = {};
  data.items.forEach(tx => {
    const from = tx.from?.hash || 'unknown';
    if (!bySource[from]) bySource[from] = { count: 0, total: 0n };
    bySource[from].count++;
    bySource[from].total += BigInt(tx.value || '0');
  });

  Object.entries(bySource)
    .sort((a, b) => Number(b[1].total - a[1].total))
    .forEach(([addr, data]) => {
      console.log(`${addr}: ${data.count} txs, ${ethers.formatEther(data.total)} ROGUE`);
    });

  // Let's check a specific tournament entry TX to see how the payout works
  console.log('');
  console.log('=== CHECKING A TOURNAMENT ENTRY TX ===');

  // Get a tournament entry transaction
  const txResponse = await fetch(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/transactions`);
  const txData = await txResponse.json();

  const tournamentEntry = txData.items.find(tx =>
    tx.to?.hash?.toLowerCase() === TOURNAMENT_CONTRACT.toLowerCase() &&
    tx.method === 'registerPlayerInSitGoROGUETournament'
  );

  if (tournamentEntry) {
    console.log('Entry TX:', tournamentEntry.hash);
    console.log('Value sent:', ethers.formatEther(tournamentEntry.value || '0'), 'ROGUE');
    console.log('URL:', `https://roguescan.io/tx/${tournamentEntry.hash}`);

    // Get the internal transactions for this specific TX
    const internalResponse = await fetch(`${EXPLORER_API}/transactions/${tournamentEntry.hash}/internal-transactions`);
    const internalData = await internalResponse.json();

    console.log('');
    console.log('Internal transactions in this TX:');
    if (internalData.items) {
      internalData.items.forEach(itx => {
        console.log(`  From: ${itx.from?.hash}`);
        console.log(`  To: ${itx.to?.hash}`);
        console.log(`  Value: ${ethers.formatEther(itx.value || '0')} ROGUE`);
        console.log('');
      });
    } else {
      console.log('  No internal transactions found');
    }
  }
}

main().catch(console.error);
