const { ethers } = require('ethers');

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

async function traceWalletOrigin(address, depth = 0, maxDepth = 3, visited = new Set()) {
  if (depth > maxDepth || visited.has(address.toLowerCase())) {
    return;
  }
  visited.add(address.toLowerCase());

  const indent = '  '.repeat(depth);
  console.log(`${indent}${'─'.repeat(50 - depth * 2)}`);
  console.log(`${indent}Tracing: ${address}`);

  const walletInfo = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}`);
  const balance = ethers.formatEther(walletInfo.coin_balance || '0');
  const type = walletInfo.is_contract ? 'Contract' : 'EOA';
  const name = walletInfo.name || '';

  console.log(`${indent}Type: ${type}${name ? ` (${name})` : ''}`);
  console.log(`${indent}Current Balance: ${balance} ROGUE`);

  // Get first transactions (sorted ascending to find origin)
  const txs = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/transactions?sort=asc`);

  if (txs.items && txs.items.length > 0) {
    // Find first incoming transactions
    const firstIncoming = txs.items.filter(tx =>
      tx.to?.hash?.toLowerCase() === address.toLowerCase() &&
      BigInt(tx.value || '0') > 0n
    ).slice(0, 5);

    if (firstIncoming.length > 0) {
      console.log(`${indent}First incoming transactions:`);
      for (const tx of firstIncoming) {
        const value = ethers.formatEther(tx.value || '0');
        const from = tx.from?.hash;
        console.log(`${indent}  ${tx.timestamp}: ${value} ROGUE from ${from?.slice(0, 10)}...`);
      }
    }
  }

  // Get internal transactions
  const internal = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/internal-transactions?sort=asc`);

  if (internal.items && internal.items.length > 0) {
    const firstInternalIn = internal.items.filter(tx =>
      tx.to?.hash?.toLowerCase() === address.toLowerCase() &&
      BigInt(tx.value || '0') > 0n
    ).slice(0, 5);

    if (firstInternalIn.length > 0) {
      console.log(`${indent}First internal incoming:`);
      for (const tx of firstInternalIn) {
        const value = ethers.formatEther(tx.value || '0');
        const from = tx.from?.hash;
        console.log(`${indent}  ${tx.timestamp}: ${value} ROGUE from ${from?.slice(0, 10)}...`);
      }
    }
  }

  // Sum up all incoming by source
  let allTxs = [];
  let nextPageParams = null;
  let pageCount = 0;

  while (pageCount < 10) { // Limit pages for performance
    pageCount++;
    let url = `${EXPLORER_API}/addresses/${address}/transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allTxs.push(...data.items);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 50));
  }

  const incomingBySource = {};
  for (const tx of allTxs) {
    if (tx.to?.hash?.toLowerCase() === address.toLowerCase()) {
      const value = BigInt(tx.value || '0');
      const from = tx.from?.hash || 'unknown';
      if (!incomingBySource[from]) incomingBySource[from] = 0n;
      incomingBySource[from] += value;
    }
  }

  const sortedSources = Object.entries(incomingBySource)
    .sort((a, b) => Number(b[1] - a[1]))
    .slice(0, 5);

  if (sortedSources.length > 0) {
    console.log(`${indent}Top direct funding sources:`);
    for (const [src, val] of sortedSources) {
      console.log(`${indent}  ${src.slice(0, 10)}...: ${ethers.formatEther(val)} ROGUE`);
    }
  }

  return sortedSources;
}

async function main() {
  console.log('='.repeat(70));
  console.log('DEEP TRACE: ORIGIN OF FUNDS FOR 0xA2b1...');
  console.log('='.repeat(70));
  console.log('');

  // The target wallet
  const target = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';

  // The main funder that sent 592M
  const mainFunder = '0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A';

  console.log('TARGET WALLET:');
  await traceWalletOrigin(target, 0, 0);

  console.log('');
  console.log('='.repeat(70));
  console.log('TRACING THE 592M ROGUE SOURCE (0x3E5884...)');
  console.log('='.repeat(70));

  // Get full history of 0x3E5884
  console.log('');
  console.log('Analyzing 0x3E5884fe... (sent 592M to target)');

  let allTxs = [];
  let nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/${mainFunder}/transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allTxs.push(...data.items);
    process.stdout.write(`\rFetching txs: ${allTxs.length}...`);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 50));
  }

  console.log(`\nTotal transactions: ${allTxs.length}`);

  // Sum incoming
  const incomingBySource = {};
  let totalDirectIn = 0n;

  for (const tx of allTxs) {
    if (tx.to?.hash?.toLowerCase() === mainFunder.toLowerCase()) {
      const value = BigInt(tx.value || '0');
      totalDirectIn += value;
      const from = tx.from?.hash || 'unknown';
      if (!incomingBySource[from]) incomingBySource[from] = { total: 0n, count: 0 };
      incomingBySource[from].total += value;
      incomingBySource[from].count++;
    }
  }

  console.log('');
  console.log('Direct incoming to 0x3E58...:', ethers.formatEther(totalDirectIn), 'ROGUE');
  console.log('');
  console.log('Incoming sources:');

  const sortedSources = Object.entries(incomingBySource)
    .sort((a, b) => Number(b[1].total - a[1].total));

  for (const [src, data] of sortedSources) {
    console.log(`  ${src}: ${ethers.formatEther(data.total)} ROGUE (${data.count} txs)`);
  }

  // Now get internal transactions
  console.log('');
  console.log('Fetching internal transactions...');

  let allInternal = [];
  nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/${mainFunder}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allInternal.push(...data.items);
    process.stdout.write(`\rFetching internal: ${allInternal.length}...`);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 50));
  }

  console.log(`\nTotal internal: ${allInternal.length}`);

  const internalBySource = {};
  let totalInternalIn = 0n;

  for (const tx of allInternal) {
    if (tx.to?.hash?.toLowerCase() === mainFunder.toLowerCase()) {
      const value = BigInt(tx.value || '0');
      totalInternalIn += value;
      const from = tx.from?.hash || 'unknown';
      if (!internalBySource[from]) internalBySource[from] = { total: 0n, count: 0 };
      internalBySource[from].total += value;
      internalBySource[from].count++;
    }
  }

  console.log('');
  console.log('Internal incoming to 0x3E58...:', ethers.formatEther(totalInternalIn), 'ROGUE');
  console.log('');
  console.log('Internal sources:');

  const sortedInternalSources = Object.entries(internalBySource)
    .sort((a, b) => Number(b[1].total - a[1].total));

  for (const [src, data] of sortedInternalSources) {
    // Get contract info
    const info = await fetchWithRetry(`${EXPLORER_API}/addresses/${src}`);
    const name = info.name || (info.is_contract ? 'Contract' : 'EOA');
    console.log(`  ${src.slice(0, 10)}... (${name}): ${ethers.formatEther(data.total)} ROGUE (${data.count} txs)`);
  }

  // Summary
  console.log('');
  console.log('='.repeat(70));
  console.log('FUND ORIGIN SUMMARY');
  console.log('='.repeat(70));
  console.log('');
  console.log('0x3E5884... received ROGUE from:');
  console.log('  - Direct transfers: ' + ethers.formatEther(totalDirectIn) + ' ROGUE');
  console.log('  - Internal (contracts): ' + ethers.formatEther(totalInternalIn) + ' ROGUE');
  console.log('  - TOTAL: ' + ethers.formatEther(totalDirectIn + totalInternalIn) + ' ROGUE');
}

main().catch(console.error);
