#!/usr/bin/env node

/**
 * Wallet Transaction History Analyzer for Rogue Chain
 * Uses Roguescan API for efficient tx history retrieval
 */

const { ethers } = require('ethers');
const fs = require('fs');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const WALLET_OF_INTEREST = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const RPC_URL = 'https://rpc.roguechain.io/rpc';
const EXPLORER_API = 'https://roguescan.io/api/v2';
const EXPLORER_URL = 'https://roguescan.io';

// Known contract addresses on Rogue Chain
const KNOWN_CONTRACTS = {
  '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789': 'EntryPoint v0.6.0',
  '0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3': 'ManagedAccountFactory',
  '0x804cA06a85083eF01C9aE94bAE771446c25269a6': 'Paymaster',
  '0xB447e3dBcF25f5C9E2894b9d9f1207c8B13DdFfd': 'RogueAccountExtension',
  '0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B': 'BuxBoosterGame (Proxy)',
  '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd': 'ROGUEBankroll',
  '0x96aB9560f1407586faE2b69Dc7f38a59BEACC594': 'NFTRewarder',
  '0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8': 'BUX Token',
  '0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5': 'moonBUX Token',
  '0x423656448374003C2cfEaFF88D5F64fb3A76487C': 'neoBUX Token',
  '0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3': 'rogueBUX Token',
  '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058': 'Tournaments Contract',
  '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60': 'Wallet of Interest',
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

async function getAllTransactions(address) {
  const allTxs = [];
  let nextPageParams = null;
  let page = 0;

  console.log('Fetching transactions from Roguescan API...');

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${address}/transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);

      if (!data.items || data.items.length === 0) break;

      allTxs.push(...data.items);
      process.stdout.write(`\rFetched ${allTxs.length} transactions (page ${page})...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      // Rate limiting
      await new Promise(r => setTimeout(r, 200));
    } catch (err) {
      console.error(`\nError fetching page ${page}: ${err.message}`);
      break;
    }
  }

  console.log(`\nTotal transactions fetched: ${allTxs.length}`);
  return allTxs;
}

async function getTokenTransfers(address) {
  const allTransfers = [];
  let nextPageParams = null;
  let page = 0;

  console.log('\nFetching token transfers from Roguescan API...');

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${address}/token-transfers`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);

      if (!data.items || data.items.length === 0) break;

      allTransfers.push(...data.items);
      process.stdout.write(`\rFetched ${allTransfers.length} token transfers (page ${page})...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 200));
    } catch (err) {
      console.error(`\nError fetching page ${page}: ${err.message}`);
      break;
    }
  }

  console.log(`\nTotal token transfers fetched: ${allTransfers.length}`);
  return allTransfers;
}

async function getInternalTransactions(address) {
  const allInternal = [];
  let nextPageParams = null;
  let page = 0;

  console.log('\nFetching internal transactions from Roguescan API...');

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${address}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);

      if (!data.items || data.items.length === 0) break;

      allInternal.push(...data.items);
      process.stdout.write(`\rFetched ${allInternal.length} internal transactions (page ${page})...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 200));
    } catch (err) {
      console.error(`\nError fetching page ${page}: ${err.message}`);
      break;
    }
  }

  console.log(`\nTotal internal transactions fetched: ${allInternal.length}`);
  return allInternal;
}

function getName(address) {
  if (!address) return '';
  const checksummed = ethers.getAddress(address);
  return KNOWN_CONTRACTS[checksummed] || KNOWN_CONTRACTS[address.toLowerCase()] || '';
}

async function main() {
  console.log('='.repeat(80));
  console.log('WALLET TRANSACTION HISTORY ANALYZER');
  console.log('='.repeat(80));
  console.log(`\nWallet: ${WALLET_ADDRESS}`);
  console.log(`Wallet of Interest: ${WALLET_OF_INTEREST}`);
  console.log(`Network: Rogue Chain (Chain ID: 560013)`);
  console.log(`Explorer: ${EXPLORER_URL}/address/${WALLET_ADDRESS}`);
  console.log('='.repeat(80));

  const provider = new ethers.JsonRpcProvider(RPC_URL);

  // Get current balance
  const currentBalance = await provider.getBalance(WALLET_ADDRESS);
  console.log(`\nCurrent ROGUE Balance: ${ethers.formatEther(currentBalance)} ROGUE`);

  // Get transaction count
  const txCount = await provider.getTransactionCount(WALLET_ADDRESS);
  console.log(`Transaction Count (Nonce): ${txCount}`);

  // Check if it's a contract
  const code = await provider.getCode(WALLET_ADDRESS);
  const isContract = code !== '0x';
  console.log(`Is Contract: ${isContract}`);

  console.log('\n' + '='.repeat(80));
  console.log('FETCHING DATA FROM ROGUESCAN...');
  console.log('='.repeat(80));

  // Fetch all data
  const transactions = await getAllTransactions(WALLET_ADDRESS);
  const tokenTransfers = await getTokenTransfers(WALLET_ADDRESS);
  const internalTxs = await getInternalTransactions(WALLET_ADDRESS);

  // Analyze transactions
  console.log('\n' + '='.repeat(80));
  console.log('ANALYZING TRANSACTIONS...');
  console.log('='.repeat(80));

  const interactions = {
    sentTo: new Map(),
    receivedFrom: new Map(),
    contractCalls: new Map(),
    methodCalls: new Map(),
    walletOfInterestTxs: [],
    tournamentTxs: [],
  };

  let totalSent = 0n;
  let totalReceived = 0n;
  let firstTxTimestamp = null;
  let lastTxTimestamp = null;

  for (const tx of transactions) {
    const from = tx.from?.hash?.toLowerCase();
    const to = tx.to?.hash?.toLowerCase();
    const value = BigInt(tx.value || '0');
    const timestamp = tx.timestamp;

    // Track first/last tx
    if (!firstTxTimestamp || timestamp < firstTxTimestamp) firstTxTimestamp = timestamp;
    if (!lastTxTimestamp || timestamp > lastTxTimestamp) lastTxTimestamp = timestamp;

    const isOutgoing = from === WALLET_ADDRESS.toLowerCase();
    const isIncoming = to === WALLET_ADDRESS.toLowerCase();

    if (isOutgoing) {
      totalSent += value;

      if (to) {
        const existing = interactions.sentTo.get(to) || { count: 0, totalValue: 0n, name: getName(to) };
        existing.count++;
        existing.totalValue += value;
        interactions.sentTo.set(to, existing);

        // Track contract calls
        if (tx.to?.is_contract) {
          const existing = interactions.contractCalls.get(to) || { count: 0, name: getName(to) || tx.to?.name || 'Unknown' };
          existing.count++;
          interactions.contractCalls.set(to, existing);
        }

        // Track method calls
        if (tx.method) {
          const existing = interactions.methodCalls.get(tx.method) || { count: 0 };
          existing.count++;
          interactions.methodCalls.set(tx.method, existing);
        }

        // Check for wallet of interest
        if (to === WALLET_OF_INTEREST.toLowerCase()) {
          interactions.walletOfInterestTxs.push({
            type: 'SENT',
            hash: tx.hash,
            value: ethers.formatEther(value),
            timestamp,
            method: tx.method,
          });
        }

        // Check for tournaments contract
        if (to === '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058'.toLowerCase()) {
          interactions.tournamentTxs.push({
            type: 'CALLED',
            hash: tx.hash,
            value: ethers.formatEther(value),
            timestamp,
            method: tx.method,
          });
        }
      }
    }

    if (isIncoming) {
      totalReceived += value;

      if (from) {
        const existing = interactions.receivedFrom.get(from) || { count: 0, totalValue: 0n, name: getName(from) };
        existing.count++;
        existing.totalValue += value;
        interactions.receivedFrom.set(from, existing);

        // Check for wallet of interest
        if (from === WALLET_OF_INTEREST.toLowerCase()) {
          interactions.walletOfInterestTxs.push({
            type: 'RECEIVED',
            hash: tx.hash,
            value: ethers.formatEther(value),
            timestamp,
            method: tx.method,
          });
        }
      }
    }
  }

  // Analyze internal transactions for wallet of interest
  for (const itx of internalTxs) {
    const from = itx.from?.hash?.toLowerCase();
    const to = itx.to?.hash?.toLowerCase();
    const value = BigInt(itx.value || '0');

    if (from === WALLET_OF_INTEREST.toLowerCase() || to === WALLET_OF_INTEREST.toLowerCase()) {
      interactions.walletOfInterestTxs.push({
        type: from === WALLET_OF_INTEREST.toLowerCase() ? 'INTERNAL_RECEIVED' : 'INTERNAL_SENT',
        hash: itx.transaction_hash,
        value: ethers.formatEther(value),
        timestamp: itx.timestamp,
        method: 'internal',
      });
    }

    // Also track internal value flows
    if (to === WALLET_ADDRESS.toLowerCase() && value > 0n) {
      totalReceived += value;
      const existing = interactions.receivedFrom.get(from) || { count: 0, totalValue: 0n, name: getName(from) };
      existing.count++;
      existing.totalValue += value;
      interactions.receivedFrom.set(from, existing);
    }
  }

  // Analyze token transfers
  const tokenSummary = new Map();

  for (const transfer of tokenTransfers) {
    const from = transfer.from?.hash?.toLowerCase();
    const to = transfer.to?.hash?.toLowerCase();
    const isOutgoing = from === WALLET_ADDRESS.toLowerCase();
    const token = transfer.token?.address || 'unknown';
    const tokenName = transfer.token?.name || transfer.token?.symbol || getName(token) || 'Unknown Token';
    const amount = BigInt(transfer.total?.value || '0');
    const decimals = parseInt(transfer.total?.decimals || '18');

    const key = `${token}_${isOutgoing ? 'SENT' : 'RECEIVED'}`;
    const existing = tokenSummary.get(key) || {
      token,
      tokenName,
      symbol: transfer.token?.symbol || '',
      type: isOutgoing ? 'SENT' : 'RECEIVED',
      count: 0,
      totalAmount: 0n,
      decimals,
    };
    existing.count++;
    existing.totalAmount += amount;
    tokenSummary.set(key, existing);

    // Check for wallet of interest in token transfers
    if (from === WALLET_OF_INTEREST.toLowerCase() || to === WALLET_OF_INTEREST.toLowerCase()) {
      interactions.walletOfInterestTxs.push({
        type: from === WALLET_OF_INTEREST.toLowerCase() ? 'TOKEN_RECEIVED' : 'TOKEN_SENT',
        hash: transfer.tx_hash,
        token: tokenName,
        amount: ethers.formatUnits(amount, decimals),
        timestamp: transfer.timestamp,
      });
    }
  }

  // Generate Report
  console.log('\n' + '='.repeat(80));
  console.log('TRANSACTION ANALYSIS REPORT');
  console.log('='.repeat(80));

  // Summary Statistics
  const outgoing = transactions.filter(tx => tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase());
  const incoming = transactions.filter(tx => tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase());

  console.log('\n--- SUMMARY ---');
  console.log(`Total Transactions: ${transactions.length}`);
  console.log(`  Outgoing: ${outgoing.length}`);
  console.log(`  Incoming: ${incoming.length}`);
  console.log(`Internal Transactions: ${internalTxs.length}`);
  console.log(`Token Transfers: ${tokenTransfers.length}`);
  console.log(`\nTotal ROGUE Sent: ${ethers.formatEther(totalSent)} ROGUE`);
  console.log(`Total ROGUE Received: ${ethers.formatEther(totalReceived)} ROGUE`);
  console.log(`Net Flow: ${ethers.formatEther(totalReceived - totalSent)} ROGUE`);
  console.log(`Current Balance: ${ethers.formatEther(currentBalance)} ROGUE`);

  if (firstTxTimestamp) {
    console.log(`\nFirst Transaction: ${new Date(firstTxTimestamp).toISOString()}`);
  }
  if (lastTxTimestamp) {
    console.log(`Last Transaction: ${new Date(lastTxTimestamp).toISOString()}`);
  }

  // Estimated starting balance
  const netFlow = totalReceived - totalSent;
  const estimatedStarting = BigInt(currentBalance.toString()) - netFlow;
  console.log(`\nEstimated Starting Balance: ~${ethers.formatEther(estimatedStarting)} ROGUE (approximate)`);

  // ==========================================
  // WALLET OF INTEREST INTERACTIONS
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log(`INTERACTIONS WITH WALLET OF INTEREST: ${WALLET_OF_INTEREST}`);
  console.log('='.repeat(80));

  if (interactions.walletOfInterestTxs.length > 0) {
    console.log(`\nFound ${interactions.walletOfInterestTxs.length} interactions:`);
    for (const tx of interactions.walletOfInterestTxs.sort((a, b) =>
      new Date(b.timestamp || 0) - new Date(a.timestamp || 0)
    )) {
      const date = tx.timestamp ? new Date(tx.timestamp).toISOString() : 'Unknown';
      console.log(`\n  ${date}`);
      console.log(`    Type: ${tx.type}`);
      if (tx.value) console.log(`    Value: ${tx.value} ROGUE`);
      if (tx.token) console.log(`    Token: ${tx.token}, Amount: ${tx.amount}`);
      if (tx.method) console.log(`    Method: ${tx.method}`);
      console.log(`    TX: ${EXPLORER_URL}/tx/${tx.hash}`);
    }
  } else {
    console.log('\nNo direct interactions found with this wallet.');
  }

  // ==========================================
  // TOURNAMENT CONTRACT INTERACTIONS
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('TOURNAMENTS CONTRACT INTERACTIONS');
  console.log('='.repeat(80));

  if (interactions.tournamentTxs.length > 0) {
    console.log(`\nFound ${interactions.tournamentTxs.length} tournament interactions:`);
    for (const tx of interactions.tournamentTxs.sort((a, b) =>
      new Date(b.timestamp || 0) - new Date(a.timestamp || 0)
    )) {
      const date = tx.timestamp ? new Date(tx.timestamp).toISOString() : 'Unknown';
      console.log(`\n  ${date}`);
      console.log(`    Method: ${tx.method || 'unknown'}`);
      console.log(`    Value: ${tx.value} ROGUE`);
      console.log(`    TX: ${EXPLORER_URL}/tx/${tx.hash}`);
    }
  } else {
    console.log('\nNo interactions found with tournaments contract.');
  }

  // ==========================================
  // CONTRACT INTERACTIONS
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('CONTRACT INTERACTIONS (by call count)');
  console.log('='.repeat(80));

  const sortedContracts = [...interactions.contractCalls.entries()]
    .sort((a, b) => b[1].count - a[1].count);

  for (const [address, data] of sortedContracts.slice(0, 30)) {
    console.log(`\n  ${data.name || 'Unknown Contract'}`);
    console.log(`    Address: ${address}`);
    console.log(`    Calls: ${data.count}`);
  }

  // ==========================================
  // METHOD CALLS
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('METHOD CALLS (by frequency)');
  console.log('='.repeat(80));

  const sortedMethods = [...interactions.methodCalls.entries()]
    .sort((a, b) => b[1].count - a[1].count);

  for (const [method, data] of sortedMethods.slice(0, 20)) {
    console.log(`  ${method}: ${data.count} calls`);
  }

  // ==========================================
  // TOP WALLETS SENT TO
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('TOP WALLETS SENT ROGUE TO');
  console.log('='.repeat(80));

  const sortedSentTo = [...interactions.sentTo.entries()]
    .sort((a, b) => Number(b[1].totalValue - a[1].totalValue));

  for (const [address, data] of sortedSentTo.slice(0, 20)) {
    console.log(`\n  ${address}`);
    if (data.name) console.log(`    Name: ${data.name}`);
    console.log(`    Transactions: ${data.count}`);
    console.log(`    Total Sent: ${ethers.formatEther(data.totalValue)} ROGUE`);
  }

  // ==========================================
  // TOP WALLETS RECEIVED FROM
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('TOP WALLETS RECEIVED ROGUE FROM');
  console.log('='.repeat(80));

  const sortedReceivedFrom = [...interactions.receivedFrom.entries()]
    .sort((a, b) => Number(b[1].totalValue - a[1].totalValue));

  for (const [address, data] of sortedReceivedFrom.slice(0, 20)) {
    console.log(`\n  ${address}`);
    if (data.name) console.log(`    Name: ${data.name}`);
    console.log(`    Transactions: ${data.count}`);
    console.log(`    Total Received: ${ethers.formatEther(data.totalValue)} ROGUE`);
  }

  // ==========================================
  // TOKEN TRANSFERS SUMMARY
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('TOKEN TRANSFERS SUMMARY');
  console.log('='.repeat(80));

  const sortedTokens = [...tokenSummary.values()]
    .sort((a, b) => b.count - a.count);

  for (const data of sortedTokens) {
    console.log(`\n  ${data.tokenName} (${data.symbol})`);
    console.log(`    Type: ${data.type}`);
    console.log(`    Transfers: ${data.count}`);
    try {
      console.log(`    Total Amount: ${ethers.formatUnits(data.totalAmount, data.decimals)}`);
    } catch {
      console.log(`    Total Amount (raw): ${data.totalAmount.toString()}`);
    }
  }

  // ==========================================
  // RECENT TRANSACTIONS
  // ==========================================
  console.log('\n' + '='.repeat(80));
  console.log('RECENT TRANSACTIONS (Last 30)');
  console.log('='.repeat(80));

  const recentTxs = transactions
    .sort((a, b) => new Date(b.timestamp || 0) - new Date(a.timestamp || 0))
    .slice(0, 30);

  for (const tx of recentTxs) {
    const from = tx.from?.hash;
    const to = tx.to?.hash;
    const isOutgoing = from?.toLowerCase() === WALLET_ADDRESS.toLowerCase();
    const date = tx.timestamp ? new Date(tx.timestamp).toISOString() : 'Unknown';
    const value = ethers.formatEther(tx.value || '0');
    const arrow = isOutgoing ? '→' : '←';
    const target = isOutgoing ? to : from;
    const targetName = getName(target) || tx.to?.name || tx.from?.name || '';

    console.log(`\n  ${date} | Block ${tx.block}`);
    console.log(`    ${isOutgoing ? 'OUTGOING' : 'INCOMING'} ${arrow} ${target?.slice(0, 14)}...`);
    if (targetName) console.log(`    Target: ${targetName}`);
    console.log(`    Value: ${value} ROGUE | Method: ${tx.method || 'transfer'}`);
    console.log(`    Status: ${tx.status || 'unknown'} | TX: ${EXPLORER_URL}/tx/${tx.hash}`);
  }

  // Save full report to file
  const report = {
    wallet: WALLET_ADDRESS,
    walletOfInterest: WALLET_OF_INTEREST,
    network: 'Rogue Chain (560013)',
    analyzedAt: new Date().toISOString(),
    currentBalance: ethers.formatEther(currentBalance),
    transactionCount: txCount,
    isContract,
    firstTransaction: firstTxTimestamp,
    lastTransaction: lastTxTimestamp,
    summary: {
      totalTransactions: transactions.length,
      internalTransactions: internalTxs.length,
      tokenTransfers: tokenTransfers.length,
      outgoing: outgoing.length,
      incoming: incoming.length,
      totalSent: ethers.formatEther(totalSent),
      totalReceived: ethers.formatEther(totalReceived),
      netFlow: ethers.formatEther(netFlow),
      estimatedStartingBalance: ethers.formatEther(estimatedStarting),
    },
    walletOfInterestInteractions: interactions.walletOfInterestTxs,
    tournamentInteractions: interactions.tournamentTxs,
    contractInteractions: Object.fromEntries(
      sortedContracts.map(([addr, data]) => [addr, data])
    ),
    methodCalls: Object.fromEntries(sortedMethods),
    topWalletsSentTo: Object.fromEntries(
      sortedSentTo.slice(0, 50).map(([addr, data]) => [addr, {
        ...data,
        totalValue: ethers.formatEther(data.totalValue)
      }])
    ),
    topWalletsReceivedFrom: Object.fromEntries(
      sortedReceivedFrom.slice(0, 50).map(([addr, data]) => [addr, {
        ...data,
        totalValue: ethers.formatEther(data.totalValue)
      }])
    ),
    tokenSummary: sortedTokens.map(t => ({
      ...t,
      totalAmount: ethers.formatUnits(t.totalAmount, t.decimals)
    })),
    recentTransactions: recentTxs.slice(0, 100).map(tx => ({
      hash: tx.hash,
      block: tx.block,
      timestamp: tx.timestamp,
      from: tx.from?.hash,
      to: tx.to?.hash,
      value: ethers.formatEther(tx.value || '0'),
      method: tx.method,
      status: tx.status,
    })),
    allTransactions: transactions.map(tx => ({
      hash: tx.hash,
      block: tx.block,
      timestamp: tx.timestamp,
      from: tx.from?.hash,
      to: tx.to?.hash,
      value: ethers.formatEther(tx.value || '0'),
      method: tx.method,
      status: tx.status,
    })),
  };

  const reportPath = `/tmp/wallet_analysis_${WALLET_ADDRESS.slice(0, 10)}_${Date.now()}.json`;
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`\n\n${'='.repeat(80)}`);
  console.log(`Full JSON report saved to: ${reportPath}`);
  console.log('='.repeat(80));
  console.log('ANALYSIS COMPLETE');
  console.log('='.repeat(80));
}

main().catch(console.error);
