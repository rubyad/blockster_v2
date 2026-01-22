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

async function analyzeContract(address, label) {
  console.log('');
  console.log('='.repeat(70));
  console.log(`ANALYZING: ${label}`);
  console.log(`Address: ${address}`);
  console.log('='.repeat(70));

  const info = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}`);
  console.log('');
  console.log('Type:', info.is_contract ? 'Contract' : 'EOA');
  console.log('Name:', info.name || 'Unknown');
  console.log('Balance:', ethers.formatEther(info.coin_balance || '0'), 'ROGUE');
  console.log('Total Transactions:', info.transactions_count || 'Unknown');

  // Check if it's a proxy and get implementation
  if (info.proxy_type) {
    console.log('Proxy Type:', info.proxy_type);
  }
  if (info.implementation_address) {
    console.log('Implementation:', info.implementation_address);
  }
  if (info.implementations && info.implementations.length > 0) {
    console.log('Implementations:');
    for (const impl of info.implementations) {
      console.log(`  - ${impl.address} (${impl.name || 'Unknown'})`);
    }
  }

  // Get creation tx
  if (info.creation_tx_hash) {
    console.log('Creation TX:', info.creation_tx_hash);
  }
  if (info.creator_address_hash) {
    console.log('Creator:', info.creator_address_hash);
  }

  // Get first transactions
  const txs = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/transactions?sort=asc`);
  if (txs.items && txs.items.length > 0) {
    console.log('');
    console.log('First 10 transactions:');
    for (let i = 0; i < Math.min(10, txs.items.length); i++) {
      const tx = txs.items[i];
      const direction = tx.from?.hash?.toLowerCase() === address.toLowerCase() ? 'OUT' : 'IN';
      const value = ethers.formatEther(tx.value || '0');
      const counterparty = direction === 'OUT' ? tx.to?.hash : tx.from?.hash;
      const method = tx.method || 'transfer';
      console.log(`  ${tx.timestamp}: ${direction} ${value} ROGUE - ${method} - ${counterparty?.slice(0, 10)}...`);
    }
  }

  // Get internal transactions
  const internal = await fetchWithRetry(`${EXPLORER_API}/addresses/${address}/internal-transactions?sort=asc`);
  if (internal.items && internal.items.length > 0) {
    console.log('');
    console.log('First 10 internal transactions:');
    for (let i = 0; i < Math.min(10, internal.items.length); i++) {
      const tx = internal.items[i];
      const direction = tx.from?.hash?.toLowerCase() === address.toLowerCase() ? 'OUT' : 'IN';
      const value = ethers.formatEther(tx.value || '0');
      const counterparty = direction === 'OUT' ? tx.to?.hash : tx.from?.hash;
      console.log(`  ${tx.timestamp}: ${direction} ${value} ROGUE - ${counterparty?.slice(0, 10)}...`);
    }
  }

  return info;
}

async function main() {
  console.log('='.repeat(70));
  console.log('IDENTIFYING THE ORIGIN OF 592M ROGUE');
  console.log('='.repeat(70));
  console.log('');
  console.log('Fund flow discovered:');
  console.log('  0x529528bE... (Contract) → 591.7M ROGUE → 0x3E5884fe... (EOA)');
  console.log('  0x3E5884fe... (EOA) → 592M ROGUE → 0xA2b101eF... (Target)');

  // The mysterious origin contract
  const originContract = '0x529528bE';

  // First, let's get the full address from the internal tx
  console.log('');
  console.log('Searching for full address of 0x529528bE...');

  const internalTxs = await fetchWithRetry(`${EXPLORER_API}/addresses/0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A/internal-transactions`);

  let fullOriginAddress = null;
  for (const tx of internalTxs.items) {
    if (tx.from?.hash?.toLowerCase().startsWith('0x529528be') && BigInt(tx.value || '0') > 500000000n * 10n**18n) {
      fullOriginAddress = tx.from.hash;
      console.log('Found full address:', fullOriginAddress);
      console.log('Value:', ethers.formatEther(tx.value), 'ROGUE');
      console.log('TX Hash:', tx.transaction_hash);
      break;
    }
  }

  if (fullOriginAddress) {
    await analyzeContract(fullOriginAddress, 'Origin Contract (591.7M source)');
  }

  // Also analyze the ROGUEBankroll since it sent 10.8M to the funder
  await analyzeContract('0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd', 'ROGUEBankroll (10.8M source)');

  // And the other contract
  await analyzeContract('0xF5d5bAF38acc367e12D9d0A9500554cDf7724460', 'Unknown Contract (134K source)');

  // Summary
  console.log('');
  console.log('='.repeat(70));
  console.log('COMPLETE FUND FLOW SUMMARY');
  console.log('='.repeat(70));
  console.log('');
  console.log('Target Wallet: 0xA2b101eF9EC4788D12b3352438cc0583dAacBf60');
  console.log('Current Balance: 299.95M ROGUE');
  console.log('');
  console.log('═══ INCOMING FUNDS ═══');
  console.log('');
  console.log('1. DIRECT TRANSFERS (597M ROGUE):');
  console.log('   └─ 0x3E5884fe... (592M): Funded by 0x529528bE... contract');
  console.log('   └─ 0x3B7c76e8... (5M): Secondary funder');
  console.log('');
  console.log('2. INTERNAL TRANSACTIONS (1.25B ROGUE):');
  console.log('   └─ ROGUEBankroll (1.15B): LP withdrawals');
  console.log('   └─ Bridge (48M): Cross-chain transfers');
  console.log('   └─ 0x6ed9... contract (47M)');
  console.log('   └─ Tournament wins (200K)');
  console.log('');
  console.log('═══ OUTGOING FUNDS ═══');
  console.log('');
  console.log('1. DIRECT TRANSFERS (1.55B ROGUE):');
  console.log('   └─ 0x282DA32f... contract (1.03B)');
  console.log('   └─ ROGUEBankroll (444M): LP deposits');
  console.log('   └─ Bridge (41M): Cross-chain');
  console.log('   └─ Other recipients (35M)');
}

main().catch(console.error);
