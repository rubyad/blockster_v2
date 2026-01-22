const { ethers } = require('ethers');

const WALLET_ADDRESS = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const EXPLORER_API = 'https://roguescan.io/api/v2';
const RPC_URL = 'https://rpc.roguechain.io/rpc';

// Known contracts
const KNOWN_CONTRACTS = {
  '0xfe962a55694aaca7b74c99d171f5cf8e0a1d5058': 'Tournament (Sit-Go)',
  '0x51db4ed2b69b598fade1acb5289c7426604ab2fd': 'ROGUEBankroll',
  '0x202aa9c1238e635e4a214d1e600179a1496404ce': 'Bridge',
  '0xbd7593ba68a8363c173c098b6fac29df52966eb5': 'WIRED Token',
  '0x97b6d6a8f2c6af6e6fb40f8d36d60df2ffe4f17b': 'BuxBoosterGame',
};

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

async function fetchAllPages(baseUrl, itemsKey = 'items') {
  const allItems = [];
  let nextPageParams = null;
  let page = 0;

  while (true) {
    page++;
    let url = baseUrl;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += (url.includes('?') ? '&' : '?') + params.toString();
    }

    try {
      const data = await fetchWithRetry(url);
      if (!data[itemsKey] || data[itemsKey].length === 0) break;

      allItems.push(...data[itemsKey]);
      process.stdout.write(`\rPage ${page}: ${allItems.length} items...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 100));
    } catch (err) {
      console.error(`\nError: ${err.message}`);
      break;
    }
  }
  console.log('');
  return allItems;
}

function getContractName(address) {
  if (!address) return 'Unknown';
  const lower = address.toLowerCase();
  return KNOWN_CONTRACTS[lower] || address.slice(0, 10) + '...';
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  console.log('='.repeat(70));
  console.log('FULL WALLET ANALYSIS');
  console.log('='.repeat(70));
  console.log('');
  console.log('Wallet:', WALLET_ADDRESS);
  console.log('');

  // Get current balance
  const balance = await provider.getBalance(WALLET_ADDRESS);
  console.log('Current ROGUE Balance:', ethers.formatEther(balance), 'ROGUE');
  console.log('');

  // Get wallet info
  const walletInfo = await fetchWithRetry(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}`);
  console.log('Total Transactions:', walletInfo.transactions_count);
  console.log('Token Transfers:', walletInfo.token_transfers_count);
  console.log('');

  // ============ DIRECT TRANSACTIONS ============
  console.log('='.repeat(70));
  console.log('FETCHING DIRECT TRANSACTIONS');
  console.log('='.repeat(70));

  const allTxs = await fetchAllPages(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/transactions`);
  console.log(`Total direct transactions: ${allTxs.length}`);

  // Separate incoming and outgoing
  const incoming = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );
  const outgoing = allTxs.filter(tx =>
    tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );

  console.log(`Incoming: ${incoming.length}`);
  console.log(`Outgoing: ${outgoing.length}`);

  // Sum direct transfers
  let directIn = 0n;
  let directOut = 0n;
  let gasPaid = 0n;

  const incomingBySource = {};
  const outgoingByDest = {};

  for (const tx of incoming) {
    const value = BigInt(tx.value || '0');
    directIn += value;

    const from = tx.from?.hash || 'unknown';
    if (!incomingBySource[from]) {
      incomingBySource[from] = { count: 0, total: 0n, txs: [] };
    }
    incomingBySource[from].count++;
    incomingBySource[from].total += value;
    incomingBySource[from].txs.push({
      hash: tx.hash,
      value: value,
      timestamp: tx.timestamp
    });
  }

  for (const tx of outgoing) {
    const value = BigInt(tx.value || '0');
    directOut += value;
    gasPaid += BigInt(tx.fee?.value || '0');

    const to = tx.to?.hash || 'unknown';
    if (!outgoingByDest[to]) {
      outgoingByDest[to] = { count: 0, total: 0n };
    }
    outgoingByDest[to].count++;
    outgoingByDest[to].total += value;
  }

  console.log('');
  console.log('Direct ROGUE received:', ethers.formatEther(directIn), 'ROGUE');
  console.log('Direct ROGUE sent:', ethers.formatEther(directOut), 'ROGUE');
  console.log('Gas paid:', ethers.formatEther(gasPaid), 'ROGUE');

  // ============ INTERNAL TRANSACTIONS ============
  console.log('');
  console.log('='.repeat(70));
  console.log('FETCHING INTERNAL TRANSACTIONS');
  console.log('='.repeat(70));

  const allInternal = await fetchAllPages(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/internal-transactions`);
  console.log(`Total internal transactions: ${allInternal.length}`);

  let internalIn = 0n;
  let internalOut = 0n;
  const internalBySource = {};
  const internalByDest = {};

  for (const tx of allInternal) {
    const value = BigInt(tx.value || '0');

    if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      internalIn += value;
      const from = tx.from?.hash || 'unknown';
      if (!internalBySource[from]) {
        internalBySource[from] = { count: 0, total: 0n };
      }
      internalBySource[from].count++;
      internalBySource[from].total += value;
    }

    if (tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      internalOut += value;
      const to = tx.to?.hash || 'unknown';
      if (!internalByDest[to]) {
        internalByDest[to] = { count: 0, total: 0n };
      }
      internalByDest[to].count++;
      internalByDest[to].total += value;
    }
  }

  console.log('');
  console.log('Internal ROGUE received:', ethers.formatEther(internalIn), 'ROGUE');
  console.log('Internal ROGUE sent:', ethers.formatEther(internalOut), 'ROGUE');

  // ============ TOKEN TRANSFERS ============
  console.log('');
  console.log('='.repeat(70));
  console.log('FETCHING TOKEN TRANSFERS');
  console.log('='.repeat(70));

  const allTokens = await fetchAllPages(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/token-transfers`);
  console.log(`Total token transfers: ${allTokens.length}`);

  const tokensBySymbol = {};
  for (const tx of allTokens) {
    const symbol = tx.token?.symbol || 'Unknown';
    if (!tokensBySymbol[symbol]) {
      tokensBySymbol[symbol] = { in: 0n, out: 0n, inCount: 0, outCount: 0 };
    }
    const value = BigInt(tx.total?.value || '0');
    if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      tokensBySymbol[symbol].in += value;
      tokensBySymbol[symbol].inCount++;
    }
    if (tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      tokensBySymbol[symbol].out += value;
      tokensBySymbol[symbol].outCount++;
    }
  }

  // ============ DETAILED ANALYSIS ============
  console.log('');
  console.log('='.repeat(70));
  console.log('INCOMING ROGUE SOURCES (DIRECT TRANSFERS)');
  console.log('='.repeat(70));
  console.log('');

  const sortedIncoming = Object.entries(incomingBySource)
    .sort((a, b) => Number(b[1].total - a[1].total));

  for (const [addr, data] of sortedIncoming) {
    const name = getContractName(addr);
    console.log(`${name}`);
    console.log(`  Address: ${addr}`);
    console.log(`  Transactions: ${data.count}`);
    console.log(`  Total: ${ethers.formatEther(data.total)} ROGUE`);

    // Show individual transactions if few
    if (data.count <= 10) {
      console.log('  Transactions:');
      for (const tx of data.txs.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp))) {
        console.log(`    - ${tx.timestamp}: ${ethers.formatEther(tx.value)} ROGUE`);
      }
    }
    console.log('');
  }

  console.log('='.repeat(70));
  console.log('INCOMING ROGUE SOURCES (INTERNAL TRANSACTIONS)');
  console.log('='.repeat(70));
  console.log('');

  const sortedInternalIn = Object.entries(internalBySource)
    .sort((a, b) => Number(b[1].total - a[1].total));

  for (const [addr, data] of sortedInternalIn) {
    const name = getContractName(addr);
    console.log(`${name}`);
    console.log(`  Address: ${addr}`);
    console.log(`  Transactions: ${data.count}`);
    console.log(`  Total: ${ethers.formatEther(data.total)} ROGUE`);
    console.log('');
  }

  console.log('='.repeat(70));
  console.log('OUTGOING ROGUE DESTINATIONS');
  console.log('='.repeat(70));
  console.log('');

  const sortedOutgoing = Object.entries(outgoingByDest)
    .sort((a, b) => Number(b[1].total - a[1].total));

  for (const [addr, data] of sortedOutgoing) {
    const name = getContractName(addr);
    console.log(`${name}`);
    console.log(`  Address: ${addr}`);
    console.log(`  Transactions: ${data.count}`);
    console.log(`  Total: ${ethers.formatEther(data.total)} ROGUE`);
    console.log('');
  }

  console.log('='.repeat(70));
  console.log('TOKEN HOLDINGS');
  console.log('='.repeat(70));
  console.log('');

  for (const [symbol, data] of Object.entries(tokensBySymbol)) {
    const net = data.in - data.out;
    console.log(`${symbol}:`);
    console.log(`  Received: ${data.inCount} txs, ${ethers.formatEther(data.in)}`);
    console.log(`  Sent: ${data.outCount} txs, ${ethers.formatEther(data.out)}`);
    console.log(`  Net: ${ethers.formatEther(net)}`);
    console.log('');
  }

  // ============ SUMMARY ============
  console.log('='.repeat(70));
  console.log('FUND FLOW SUMMARY');
  console.log('='.repeat(70));
  console.log('');

  const totalIn = directIn + internalIn;
  const totalOut = directOut + internalOut + gasPaid;

  console.log('TOTAL INCOMING:');
  console.log(`  Direct transfers: ${ethers.formatEther(directIn)} ROGUE`);
  console.log(`  Internal transactions: ${ethers.formatEther(internalIn)} ROGUE`);
  console.log(`  TOTAL: ${ethers.formatEther(totalIn)} ROGUE`);
  console.log('');
  console.log('TOTAL OUTGOING:');
  console.log(`  Direct transfers: ${ethers.formatEther(directOut)} ROGUE`);
  console.log(`  Internal transactions: ${ethers.formatEther(internalOut)} ROGUE`);
  console.log(`  Gas fees: ${ethers.formatEther(gasPaid)} ROGUE`);
  console.log(`  TOTAL: ${ethers.formatEther(totalOut)} ROGUE`);
  console.log('');
  console.log('NET FLOW:', ethers.formatEther(totalIn - totalOut), 'ROGUE');
  console.log('CURRENT BALANCE:', ethers.formatEther(balance), 'ROGUE');
  console.log('');

  // Check for discrepancy
  const expectedBalance = totalIn - totalOut;
  const actualBalance = balance;
  const discrepancy = actualBalance - expectedBalance;

  if (discrepancy !== 0n) {
    console.log('='.repeat(70));
    console.log('ACCOUNTING DISCREPANCY');
    console.log('='.repeat(70));
    console.log('');
    console.log(`Expected balance: ${ethers.formatEther(expectedBalance)} ROGUE`);
    console.log(`Actual balance: ${ethers.formatEther(actualBalance)} ROGUE`);
    console.log(`Discrepancy: ${ethers.formatEther(discrepancy)} ROGUE`);
  }

  // Check genesis
  console.log('');
  console.log('='.repeat(70));
  console.log('GENESIS CHECK');
  console.log('='.repeat(70));
  console.log('');

  for (const blockNum of [0, 1, 100, 1000]) {
    try {
      const bal = await provider.getBalance(WALLET_ADDRESS, blockNum);
      console.log(`Block ${blockNum}: ${ethers.formatEther(bal)} ROGUE`);
    } catch (err) {
      console.log(`Block ${blockNum}: Error`);
    }
  }
}

main().catch(console.error);
