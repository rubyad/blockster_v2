const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60'.toLowerCase();

async function fetchAllLogs(address) {
  const all = [];
  let next = null;
  let pages = 0;

  while (pages < 200) {
    pages++;
    let url = `${EXPLORER_API}/addresses/${address}/logs`;
    if (next) url += '?' + new URLSearchParams(next).toString();

    const response = await fetch(url);
    const data = await response.json();
    if (!data.items || data.items.length === 0) break;
    all.push(...data.items);
    process.stderr.write(`\rFetched ${all.length} logs...`);
    if (!data.next_page_params) break;
    next = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }
  process.stderr.write('\n');
  return all;
}

async function main() {
  console.log('='.repeat(70));
  console.log('ROGUETRADER BETTING P&L ANALYSIS');
  console.log('='.repeat(70));
  console.log('');
  console.log('Wallet:', WALLET);
  console.log('');

  // Fetch all logs from RogueTrader
  console.log('Fetching all BetSettled events from RogueTrader...');
  const allLogs = await fetchAllLogs(ROGUETRADER);

  // Filter to BetSettled events for our wallet
  const betSettledLogs = allLogs.filter(log => {
    const event = log.decoded?.method_call || '';
    if (!event.includes('BetSettled')) return false;

    const params = log.decoded?.parameters || [];
    for (const p of params) {
      if (p.name === 'owner' && p.value?.toLowerCase() === WALLET) {
        return true;
      }
    }
    return false;
  });

  console.log(`Found ${betSettledLogs.length} BetSettled events for wallet`);
  console.log('');

  // Also count BetPlaced events
  const betPlacedLogs = allLogs.filter(log => {
    const event = log.decoded?.method_call || '';
    if (!event.includes('BetPlaced')) return false;

    const params = log.decoded?.parameters || [];
    for (const p of params) {
      if (p.name === 'owner' && p.value?.toLowerCase() === WALLET) {
        return true;
      }
    }
    return false;
  });

  console.log(`Found ${betPlacedLogs.length} BetPlaced events for wallet`);
  console.log('');

  // Analyze settlements
  let wins = 0;
  let losses = 0;
  let totalWagered = 0n;
  let totalPayout = 0n;

  for (const log of betSettledLogs) {
    const params = log.decoded?.parameters || [];
    let wagerAmount = 0n;
    let payout = 0n;
    let winner = false;

    for (const p of params) {
      if (p.name === 'wagerAmount') wagerAmount = BigInt(p.value || '0');
      if (p.name === 'payout') payout = BigInt(p.value || '0');
      if (p.name === 'winner') winner = p.value === 'true' || p.value === true;
    }

    totalWagered += wagerAmount;
    totalPayout += payout;

    if (winner) {
      wins++;
    } else {
      losses++;
    }
  }

  console.log('='.repeat(70));
  console.log('BETTING RESULTS (from BetSettled events)');
  console.log('='.repeat(70));
  console.log('');
  console.log(`Settled bets: ${betSettledLogs.length}`);
  console.log(`  Wins: ${wins}`);
  console.log(`  Losses: ${losses}`);
  console.log(`  Win rate: ${(wins / (wins + losses) * 100).toFixed(1)}%`);
  console.log('');
  console.log(`Total wagered: ${ethers.formatEther(totalWagered)} ROGUE`);
  console.log(`Total payout: ${ethers.formatEther(totalPayout)} ROGUE`);
  console.log('');

  const pnl = totalPayout - totalWagered;
  console.log(`NET P&L: ${ethers.formatEther(pnl)} ROGUE ${pnl >= 0n ? '✅ PROFIT' : '❌ LOSS'}`);

  if (totalWagered > 0n) {
    const roi = Number(pnl * 10000n / totalWagered) / 100;
    console.log(`ROI: ${roi >= 0 ? '+' : ''}${roi.toFixed(2)}%`);
  }

  // Check for unsettled bets
  const placedBetIds = new Set();
  for (const log of betPlacedLogs) {
    const params = log.decoded?.parameters || [];
    for (const p of params) {
      if (p.name === 'betId') placedBetIds.add(p.value);
    }
  }

  const settledBetIds = new Set();
  for (const log of betSettledLogs) {
    const params = log.decoded?.parameters || [];
    for (const p of params) {
      if (p.name === 'betId') settledBetIds.add(p.value);
    }
  }

  const unsettled = [...placedBetIds].filter(id => !settledBetIds.has(id));
  console.log('');
  console.log(`Placed bets: ${placedBetIds.size}`);
  console.log(`Settled bets: ${settledBetIds.size}`);
  console.log(`Unsettled bets: ${unsettled.length}`);

  // Sample of recent wins
  console.log('');
  console.log('='.repeat(70));
  console.log('SAMPLE RECENT WINS');
  console.log('='.repeat(70));
  console.log('');

  let sampleCount = 0;
  for (const log of betSettledLogs) {
    const params = log.decoded?.parameters || [];
    let winner = false;
    let wagerAmount = 0n;
    let payout = 0n;

    for (const p of params) {
      if (p.name === 'winner') winner = p.value === 'true' || p.value === true;
      if (p.name === 'wagerAmount') wagerAmount = BigInt(p.value || '0');
      if (p.name === 'payout') payout = BigInt(p.value || '0');
    }

    if (winner && sampleCount < 5) {
      sampleCount++;
      const profit = payout - wagerAmount;
      console.log(`Bet: ${ethers.formatEther(wagerAmount)} ROGUE → Won ${ethers.formatEther(payout)} ROGUE (+${ethers.formatEther(profit)} profit)`);
    }
  }
}

main().catch(console.error);
