/**
 * Query Roguescan API for internal transactions from Tournament contract to wallet
 */

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const TOURNAMENT_CONTRACT = '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058';
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

async function getInternalTxsFromContract(contractAddress) {
  const allInternal = [];
  let nextPageParams = null;
  let page = 0;

  console.log(`Fetching internal transactions FROM ${contractAddress}...`);

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${contractAddress}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);

      if (!data.items || data.items.length === 0) break;

      // Filter to only txs TO our wallet
      const toWallet = data.items.filter(tx =>
        tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
      );

      allInternal.push(...toWallet);
      process.stdout.write(`\rPage ${page}: Found ${allInternal.length} txs to wallet...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 200));

      // Safety limit
      if (page > 500) {
        console.log('\nReached page limit');
        break;
      }
    } catch (err) {
      console.error(`\nError fetching page ${page}: ${err.message}`);
      break;
    }
  }

  return allInternal;
}

async function main() {
  console.log('=== TOURNAMENT CONTRACT INTERNAL TRANSACTIONS ===');
  console.log('Wallet:', WALLET_ADDRESS);
  console.log('Tournament:', TOURNAMENT_CONTRACT);
  console.log('');

  const internalTxs = await getInternalTxsFromContract(TOURNAMENT_CONTRACT);

  console.log(`\n\nTotal internal txs to wallet: ${internalTxs.length}`);

  // Calculate total
  let totalReceived = 0n;
  const byDate = {};

  internalTxs.forEach(tx => {
    const value = BigInt(tx.value || '0');
    totalReceived += value;

    const date = tx.timestamp ? tx.timestamp.slice(0, 10) : 'unknown';
    if (!byDate[date]) byDate[date] = { count: 0, value: 0n };
    byDate[date].count++;
    byDate[date].value += value;
  });

  const { ethers } = require('ethers');

  console.log('\n=== TOTAL RECEIVED FROM TOURNAMENT CONTRACT ===');
  console.log('Total:', ethers.formatEther(totalReceived), 'ROGUE');
  console.log('Transaction count:', internalTxs.length);

  console.log('\n=== BY DATE ===');
  const sortedDates = Object.keys(byDate).sort();
  sortedDates.forEach(date => {
    const d = byDate[date];
    console.log(`${date}: ${d.count} txs, ${ethers.formatEther(d.value)} ROGUE`);
  });

  // Compare to what we found before
  console.log('\n=== COMPARISON ===');
  console.log('Previously found (from wallet internal-txs endpoint): 4,019,341,000 ROGUE');
  console.log('Now found (from contract internal-txs endpoint):', ethers.formatEther(totalReceived), 'ROGUE');

  // Show sample transactions
  console.log('\n=== SAMPLE TRANSACTIONS (first 10) ===');
  internalTxs.slice(0, 10).forEach(tx => {
    console.log(`  ${tx.timestamp}: ${ethers.formatEther(tx.value || '0')} ROGUE`);
    console.log(`    TX: https://roguescan.io/tx/${tx.transaction_hash}`);
  });
}

main().catch(console.error);
