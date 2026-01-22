const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60'.toLowerCase();

async function main() {
  // Get recent transactions TO the RogueTrader contract to see what methods are called
  const response = await fetch(`${EXPLORER_API}/addresses/${ROGUETRADER}/transactions`);
  const data = await response.json();

  const methods = {};
  for (const tx of data.items) {
    const method = tx.method || 'unknown';
    if (!methods[method]) methods[method] = 0;
    methods[method]++;
  }

  console.log('Methods called on RogueTrader (first page):');
  for (const [m, c] of Object.entries(methods).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${m}: ${c}`);
  }

  // Check if there's a settle or claim method
  console.log('');
  console.log('Looking for settlement transactions...');

  const settleTx = data.items.find(tx =>
    tx.method?.toLowerCase().includes('settle') ||
    tx.method?.toLowerCase().includes('claim') ||
    tx.method?.toLowerCase().includes('resolve') ||
    tx.method?.toLowerCase().includes('execute')
  );

  if (settleTx) {
    console.log('Found settlement tx:', settleTx.hash);
    console.log('Method:', settleTx.method);

    // Get internal txs
    const internal = await fetch(`${EXPLORER_API}/transactions/${settleTx.hash}/internal-transactions`).then(r => r.json());
    console.log('');
    console.log('Internal transactions:');
    for (const itx of internal.items || []) {
      console.log(`  From: ${itx.from?.hash?.slice(0, 10)}...`);
      console.log(`  To: ${itx.to?.hash?.slice(0, 10)}...`);
      console.log(`  Value: ${ethers.formatEther(itx.value || '0')} ROGUE`);
      console.log('  ---');
    }
  }

  // Now look for any transactions that pay to our wallet
  console.log('');
  console.log('='.repeat(50));
  console.log('Checking internal txs from ALL contracts to wallet...');

  const walletInternal = await fetch(`${EXPLORER_API}/addresses/${WALLET}/internal-transactions`).then(r => r.json());

  // Group by source
  const bySource = {};
  for (const tx of walletInternal.items) {
    if (tx.to?.hash?.toLowerCase() === WALLET && BigInt(tx.value || '0') > 0n) {
      const from = tx.from?.hash || 'unknown';
      if (!bySource[from]) bySource[from] = { count: 0, total: 0n };
      bySource[from].count++;
      bySource[from].total += BigInt(tx.value || '0');
    }
  }

  console.log('');
  console.log('Internal tx sources to wallet (first page):');
  for (const [addr, data] of Object.entries(bySource).sort((a, b) => Number(b[1].total - a[1].total))) {
    console.log(`  ${addr.slice(0, 10)}...: ${data.count} txs, ${ethers.formatEther(data.total)} ROGUE`);
  }

  // Check specifically what contract is paying out
  console.log('');
  console.log('='.repeat(50));
  console.log('The payout flow for RogueTrader bets:');
  console.log('');
  console.log('1. User calls placeBet() on RogueTrader');
  console.log('2. RogueTrader forwards bet to ROGUEBankroll');
  console.log('3. When bet settles, ROGUEBankroll pays the winner');
  console.log('');
  console.log('So winnings come from ROGUEBankroll (0x51DB4eD2...), NOT RogueTrader!');
  console.log('');
  console.log('This means we cannot distinguish betting winnings from LP withdrawals');
  console.log('by looking at internal transactions alone - they all come from the same source.');
}

main().catch(console.error);
