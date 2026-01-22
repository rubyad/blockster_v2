const { ethers } = require('ethers');

const WALLET_ADDRESS = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const EXPLORER_API = 'https://roguescan.io/api/v2';

// Main funding sources to trace
const FUNDING_SOURCES = [
  {
    address: '0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A',
    name: 'Main Funder',
    amount: '592M ROGUE'
  },
  {
    address: '0x3B7c76e86731d07707516530B8FB97721f038229',
    name: 'Secondary Funder',
    amount: '5M ROGUE'
  },
  {
    address: '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd',
    name: 'ROGUEBankroll',
    amount: '1.15B ROGUE (withdrawals)'
  }
];

// Key recipients
const KEY_RECIPIENTS = [
  {
    address: '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A',
    name: 'Main Recipient',
    amount: '1.03B ROGUE'
  }
];

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

async function analyzeWallet(address, name) {
  console.log(`\n${'='.repeat(70)}`);
  console.log(`ANALYZING: ${name}`);
  console.log(`Address: ${address}`);
  console.log('='.repeat(70));

  const walletInfo = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}`);
  console.log('');
  console.log('Balance:', ethers.formatEther(walletInfo.coin_balance || '0'), 'ROGUE');
  console.log('Type:', walletInfo.is_contract ? 'Contract' : 'EOA');
  if (walletInfo.name) console.log('Contract Name:', walletInfo.name);

  // Get first page of transactions to understand activity
  const txs = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/transactions?sort=asc`);

  if (txs.items && txs.items.length > 0) {
    console.log('');
    console.log('First transactions:');
    for (let i = 0; i < Math.min(5, txs.items.length); i++) {
      const tx = txs.items[i];
      const direction = tx.from?.hash?.toLowerCase() === address.toLowerCase() ? 'OUT' : 'IN';
      const value = ethers.formatEther(tx.value || '0');
      const counterparty = direction === 'OUT' ? tx.to?.hash : tx.from?.hash;
      console.log(`  ${tx.timestamp}: ${direction} ${value} ROGUE ${direction === 'OUT' ? 'to' : 'from'} ${counterparty?.slice(0, 10)}...`);
    }
  }

  // Get internal transactions
  const internal = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/internal-transactions`);
  if (internal.items && internal.items.length > 0) {
    console.log('');
    console.log(`Internal transactions: ${internal.items.length}+ (first page)`);

    // Sum internal by source
    const bySource = {};
    for (const tx of internal.items) {
      if (tx.to?.hash?.toLowerCase() === address.toLowerCase()) {
        const from = tx.from?.hash || 'unknown';
        if (!bySource[from]) bySource[from] = 0n;
        bySource[from] += BigInt(tx.value || '0');
      }
    }

    if (Object.keys(bySource).length > 0) {
      console.log('Internal incoming sources (first page):');
      for (const [src, val] of Object.entries(bySource).sort((a, b) => Number(b[1] - a[1]))) {
        console.log(`  ${src.slice(0, 10)}...: ${ethers.formatEther(val)} ROGUE`);
      }
    }
  }

  return walletInfo;
}

async function main() {
  console.log('='.repeat(70));
  console.log('TRACING FUNDING SOURCES FOR WALLET');
  console.log('='.repeat(70));
  console.log('');
  console.log('Target Wallet:', WALLET_ADDRESS);
  console.log('');
  console.log('KEY FINDINGS FROM INITIAL ANALYSIS:');
  console.log('- Current Balance: 299.95M ROGUE');
  console.log('- Total Received: 1.85B ROGUE');
  console.log('- Total Sent: 1.55B ROGUE');
  console.log('');
  console.log('MAIN INCOME SOURCES:');
  console.log('1. ROGUEBankroll withdrawals: 1.15B ROGUE (2,063 txs)');
  console.log('2. Direct from 0x3E58...: 592M ROGUE (3 txs)');
  console.log('3. Bridge: 48M ROGUE (11 txs)');
  console.log('4. 0x6ed9...: 47M ROGUE (58 txs)');
  console.log('5. Direct from 0x3B7c...: 5M ROGUE (1 tx)');
  console.log('');
  console.log('MAIN DESTINATIONS:');
  console.log('1. 0x282D...: 1.03B ROGUE (4,023 txs)');
  console.log('2. ROGUEBankroll deposits: 444M ROGUE (288 txs)');
  console.log('3. Bridge: 41M ROGUE (30 txs)');

  // Analyze the main funder
  await analyzeWallet('0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A', 'Main Funder (592M sender)');

  // Analyze secondary funder
  await analyzeWallet('0x3B7c76e86731d07707516530B8FB97721f038229', 'Secondary Funder (5M sender)');

  // Analyze the main recipient
  await analyzeWallet('0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A', 'Main Recipient (1.03B receiver)');

  // Analyze the mysterious 0x6ed9 source
  await analyzeWallet('0x6ed91824BCa568f7543C54333a1a3998e8cA4b32', 'Internal Source 0x6ed9 (47M)');

  // Summary
  console.log('');
  console.log('='.repeat(70));
  console.log('SUMMARY');
  console.log('='.repeat(70));
  console.log('');
  console.log('FUND FLOW PATTERN:');
  console.log('');
  console.log('1. INITIAL FUNDING:');
  console.log('   - 592M ROGUE from 0x3E5884... (likely treasury/founder)');
  console.log('   - 5M ROGUE from 0x3B7c76...');
  console.log('   - 48M ROGUE bridged from other chains');
  console.log('');
  console.log('2. BANKROLL ACTIVITY:');
  console.log('   - Deposited 444M ROGUE to ROGUEBankroll');
  console.log('   - Withdrew 1.15B ROGUE from ROGUEBankroll');
  console.log('   - NET: +709M ROGUE from LP earnings/withdrawals');
  console.log('');
  console.log('3. DISTRIBUTION:');
  console.log('   - Sent 1.03B ROGUE to 0x282D... (likely ops/distribution wallet)');
  console.log('   - Sent 41M ROGUE to bridge (cross-chain transfers)');
  console.log('');
  console.log('4. CURRENT STATE:');
  console.log('   - 300M ROGUE balance');
  console.log('   - 112M LP-ROGUE tokens (bankroll shares)');
}

main().catch(console.error);
