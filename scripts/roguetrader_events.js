const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';
const ROGUEBANKROLL = '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd';

async function fetchAll(url) {
  const all = [];
  let next = null;
  let pages = 0;
  while (pages < 100) { // Limit pages
    pages++;
    let fullUrl = url;
    if (next) fullUrl += (url.includes('?') ? '&' : '?') + new URLSearchParams(next).toString();
    const response = await fetch(fullUrl);
    const data = await response.json();
    if (!data.items || data.items.length === 0) break;
    all.push(...data.items);
    process.stderr.write(`\rFetched ${all.length}...`);
    if (!data.next_page_params) break;
    next = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }
  process.stderr.write('\n');
  return all;
}

async function main() {
  console.log('='.repeat(70));
  console.log('ROGUETRADER EVENT LOG ANALYSIS');
  console.log('='.repeat(70));
  console.log('');

  // Get logs/events for this wallet from RogueTrader
  console.log('Fetching transaction logs for wallet...');

  // Get all transactions from wallet
  const allTxs = await fetchAll(`${EXPLORER_API}/addresses/${WALLET}/transactions`);

  // Filter to RogueTrader transactions
  const rogueTraderTxs = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === ROGUETRADER.toLowerCase()
  );

  console.log(`Found ${rogueTraderTxs.length} RogueTrader transactions`);
  console.log('');

  // Analyze a sample of transactions to find bet outcomes
  console.log('Analyzing transaction logs to find bet outcomes...');
  console.log('');

  let totalWagered = 0n;
  let totalWon = 0n;
  let wins = 0;
  let losses = 0;
  let pending = 0;
  const sampleSize = Math.min(100, rogueTraderTxs.length);

  for (let i = 0; i < sampleSize; i++) {
    const tx = rogueTraderTxs[i];
    if (tx.method !== 'placeBet') continue;

    const betAmount = BigInt(tx.value || '0');
    totalWagered += betAmount;

    // Get logs for this transaction
    try {
      const logs = await fetch(`${EXPLORER_API}/transactions/${tx.hash}/logs`).then(r => r.json());

      let betId = null;
      let outcome = null;
      let payout = 0n;

      for (const log of logs.items || []) {
        const eventName = log.decoded?.method_call || '';

        // BetPlaced event
        if (eventName.includes('BetPlaced')) {
          const params = log.decoded?.parameters || [];
          for (const p of params) {
            if (p.name === 'betId') betId = p.value;
          }
        }

        // Look for settlement events
        if (eventName.includes('BetSettled') || eventName.includes('BetResolved') || eventName.includes('Payout')) {
          const params = log.decoded?.parameters || [];
          for (const p of params) {
            if (p.name === 'payout' || p.name === 'amount' || p.name === 'winAmount') {
              payout = BigInt(p.value || '0');
            }
            if (p.name === 'won' || p.name === 'isWinner') {
              outcome = p.value === 'true' || p.value === true;
            }
          }
        }
      }

      if (payout > 0n) {
        wins++;
        totalWon += payout;
        if (wins <= 5) {
          console.log(`WIN: Bet ${ethers.formatEther(betAmount)} → Won ${ethers.formatEther(payout)} ROGUE`);
        }
      } else if (outcome === false) {
        losses++;
        if (losses <= 5) {
          console.log(`LOSS: Bet ${ethers.formatEther(betAmount)} ROGUE`);
        }
      } else {
        pending++;
      }

    } catch (err) {
      // Skip errors
    }

    await new Promise(r => setTimeout(r, 50));
    process.stderr.write(`\rProcessed ${i + 1}/${sampleSize}...`);
  }

  console.log('');
  console.log('');
  console.log('='.repeat(70));
  console.log(`SAMPLE RESULTS (${sampleSize} transactions)`);
  console.log('='.repeat(70));
  console.log('');
  console.log(`Wins: ${wins}`);
  console.log(`Losses: ${losses}`);
  console.log(`Pending/Unknown: ${pending}`);
  console.log('');
  console.log(`Sample wagered: ${ethers.formatEther(totalWagered)} ROGUE`);
  console.log(`Sample won: ${ethers.formatEther(totalWon)} ROGUE`);

  if (wins + losses > 0) {
    const winRate = (wins / (wins + losses) * 100).toFixed(1);
    console.log(`Win rate: ${winRate}%`);
  }

  // Extrapolate
  console.log('');
  console.log('='.repeat(70));
  console.log('EXTRAPOLATED FULL BETTING STATS');
  console.log('='.repeat(70));
  console.log('');
  console.log(`Total bets: ${rogueTraderTxs.filter(tx => tx.method === 'placeBet').length}`);

  // Get total wagered from all bets
  let fullWagered = 0n;
  for (const tx of rogueTraderTxs) {
    if (tx.method === 'placeBet') {
      fullWagered += BigInt(tx.value || '0');
    }
  }
  console.log(`Total wagered: ${ethers.formatEther(fullWagered)} ROGUE`);

  if (wins > 0 && sampleSize > 0) {
    const avgWinPayout = totalWon / BigInt(wins);
    const winRate = wins / (wins + losses);
    const estimatedWins = Math.round(rogueTraderTxs.length * winRate);
    const estimatedWinnings = avgWinPayout * BigInt(estimatedWins);

    console.log('');
    console.log(`Estimated win rate: ${(winRate * 100).toFixed(1)}%`);
    console.log(`Estimated total winnings: ${ethers.formatEther(estimatedWinnings)} ROGUE`);
    console.log(`Estimated P&L: ${ethers.formatEther(estimatedWinnings - fullWagered)} ROGUE`);
  }
}

main().catch(console.error);
