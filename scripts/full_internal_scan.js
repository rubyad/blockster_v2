/**
 * Scan ALL internal transactions to the wallet to find every source of funds
 */

const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const EXPLORER_API = 'https://roguescan.io/api/v2';

async function fetchWithRetry(url, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.json();
    } catch (err) {
      if (i === retries - 1) throw err;
      await new Promise(r => setTimeout(r, 1000 * (i + 1)));
    }
  }
}

async function main() {
  console.log('=== FULL INTERNAL TRANSACTION SCAN ===');
  console.log('Wallet:', WALLET_ADDRESS);
  console.log('');

  // Fetch ALL internal transactions
  const allInternal = [];
  let nextPageParams = null;
  let page = 0;

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);
      if (!data.items || data.items.length === 0) break;

      allInternal.push(...data.items);
      process.stdout.write(`\rPage ${page}: ${allInternal.length} internal txs...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 150));
    } catch (err) {
      console.error(`\nError: ${err.message}`);
      break;
    }
  }

  console.log(`\n\nTotal internal transactions: ${allInternal.length}`);

  // Separate incoming vs outgoing
  const incoming = allInternal.filter(tx =>
    tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );
  const outgoing = allInternal.filter(tx =>
    tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );

  console.log(`Incoming: ${incoming.length}`);
  console.log(`Outgoing: ${outgoing.length}`);

  // Sum up totals
  let totalIncoming = 0n;
  let totalOutgoing = 0n;

  const bySourceIncoming = {};
  incoming.forEach(tx => {
    const value = BigInt(tx.value || '0');
    totalIncoming += value;

    const from = tx.from?.hash || 'unknown';
    if (!bySourceIncoming[from]) bySourceIncoming[from] = { count: 0, total: 0n };
    bySourceIncoming[from].count++;
    bySourceIncoming[from].total += value;
  });

  outgoing.forEach(tx => {
    totalOutgoing += BigInt(tx.value || '0');
  });

  console.log('');
  console.log('=== TOTALS ===');
  console.log('Total INCOMING from internal txs:', ethers.formatEther(totalIncoming), 'ROGUE');
  console.log('Total OUTGOING from internal txs:', ethers.formatEther(totalOutgoing), 'ROGUE');

  console.log('');
  console.log('=== INCOMING BY SOURCE ===');
  const sortedSources = Object.entries(bySourceIncoming)
    .sort((a, b) => Number(b[1].total - a[1].total));

  sortedSources.forEach(([addr, data]) => {
    console.log(`${addr}:`);
    console.log(`  Count: ${data.count}, Total: ${ethers.formatEther(data.total)} ROGUE`);
  });

  // Calculate the discrepancy
  console.log('');
  console.log('=== FUND FLOW ANALYSIS ===');
  console.log('');
  console.log('Direct incoming (6 txs): 7,502,276 ROGUE');
  console.log('Internal incoming:', ethers.formatEther(totalIncoming), 'ROGUE');
  const totalIn = 7502276n * 10n**18n + totalIncoming;
  console.log('TOTAL IN:', ethers.formatEther(totalIn), 'ROGUE');
  console.log('');
  console.log('Direct outgoing (14,891 txs): ~4,567,010,015 ROGUE');
  console.log('Internal outgoing:', ethers.formatEther(totalOutgoing), 'ROGUE');
  console.log('');
  console.log('Current balance: 6,725 ROGUE');
  console.log('');

  // The math
  const directOut = 4567010015n * 10n**18n;
  const currentBalance = 6725887878850650320567n;

  // Starting = Current - In + Out
  const totalInWei = 7502276n * 10n**18n + totalIncoming;
  const totalOutWei = directOut + totalOutgoing;
  const startingBalance = currentBalance - totalInWei + totalOutWei;

  console.log('=== CALCULATED STARTING BALANCE ===');
  console.log('Formula: Starting = Current - TotalIn + TotalOut');
  console.log('Starting balance:', ethers.formatEther(startingBalance), 'ROGUE');
  console.log('');

  if (startingBalance > 0n) {
    console.log('DISCREPANCY: The wallet appears to have started with', ethers.formatEther(startingBalance), 'ROGUE');
    console.log('This is impossible for an EOA without prior funding.');
    console.log('');
    console.log('POSSIBLE EXPLANATIONS:');
    console.log('1. Genesis allocation at chain launch');
    console.log('2. Airdrop or reward distribution we havent captured');
    console.log('3. Internal txs from other contracts we missed');
    console.log('4. API data is incomplete');
  }
}

main().catch(console.error);
