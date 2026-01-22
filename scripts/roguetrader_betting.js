const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';

async function fetchAll(url) {
  const all = [];
  let next = null;
  while (true) {
    let fullUrl = url;
    if (next) fullUrl += '?' + new URLSearchParams(next).toString();
    const response = await fetch(fullUrl);
    const data = await response.json();
    if (!data.items || data.items.length === 0) break;
    all.push(...data.items);
    process.stderr.write('\rFetched ' + all.length + '...');
    if (!data.next_page_params) break;
    next = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }
  process.stderr.write('\n');
  return all;
}

async function main() {
  console.log('='.repeat(70));
  console.log('ROGUETRADER BETTING ANALYSIS');
  console.log('='.repeat(70));
  console.log('');
  console.log('Wallet:', WALLET);
  console.log('RogueTrader Contract:', ROGUETRADER);
  console.log('');

  // Get all txs to RogueTrader
  console.log('Fetching all transactions...');
  const allTxs = await fetchAll(`${EXPLORER_API}/addresses/${WALLET}/transactions`);

  const bets = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === ROGUETRADER.toLowerCase()
  );

  console.log('');
  console.log('='.repeat(70));
  console.log('BETS PLACED');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total bet transactions:', bets.length);

  let totalBet = 0n;
  const byMethod = {};
  for (const tx of bets) {
    totalBet += BigInt(tx.value || '0');
    const method = tx.method || 'unknown';
    if (!byMethod[method]) byMethod[method] = { count: 0, value: 0n };
    byMethod[method].count++;
    byMethod[method].value += BigInt(tx.value || '0');
  }

  console.log('Total wagered:', ethers.formatEther(totalBet), 'ROGUE');
  console.log('');
  console.log('By method:');
  for (const [m, d] of Object.entries(byMethod).sort((a, b) => b[1].count - a[1].count)) {
    console.log(`  ${m}: ${d.count} txs, ${ethers.formatEther(d.value)} ROGUE`);
  }

  // Get internal txs (winnings from RogueTrader)
  console.log('');
  console.log('Fetching winnings (internal transactions)...');
  const allInternal = await fetchAll(`${EXPLORER_API}/addresses/${WALLET}/internal-transactions`);

  const winnings = allInternal.filter(tx =>
    tx.from?.hash?.toLowerCase() === ROGUETRADER.toLowerCase() &&
    tx.to?.hash?.toLowerCase() === WALLET.toLowerCase()
  );

  let totalWon = 0n;
  for (const tx of winnings) {
    totalWon += BigInt(tx.value || '0');
  }

  console.log('');
  console.log('='.repeat(70));
  console.log('WINNINGS RECEIVED');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total winning transactions:', winnings.length);
  console.log('Total won:', ethers.formatEther(totalWon), 'ROGUE');

  // Calculate P&L
  console.log('');
  console.log('='.repeat(70));
  console.log('PROFIT / LOSS SUMMARY');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total wagered:', ethers.formatEther(totalBet), 'ROGUE');
  console.log('Total won:', ethers.formatEther(totalWon), 'ROGUE');

  const pnl = totalWon - totalBet;
  const pnlSign = pnl >= 0n ? '+' : '';
  console.log('');
  console.log(`NET P&L: ${pnlSign}${ethers.formatEther(pnl)} ROGUE ${pnl >= 0n ? '✅ PROFIT' : '❌ LOSS'}`);

  if (totalBet > 0n) {
    const roi = Number(pnl * 10000n / totalBet) / 100;
    console.log(`ROI: ${roi >= 0 ? '+' : ''}${roi.toFixed(2)}%`);

    const winRate = (winnings.length / bets.length * 100).toFixed(1);
    console.log(`Win rate: ${winRate}% (${winnings.length} wins / ${bets.length} bets)`);

    if (bets.length > 0) {
      const avgBet = totalBet / BigInt(bets.length);
      console.log(`Average bet size: ${ethers.formatEther(avgBet)} ROGUE`);
    }
    if (winnings.length > 0) {
      const avgWin = totalWon / BigInt(winnings.length);
      console.log(`Average win size: ${ethers.formatEther(avgWin)} ROGUE`);
    }
  }
}

main().catch(console.error);
