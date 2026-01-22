const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';
const ROGUEBANKROLL = '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd';

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
  console.log('ROGUETRADER BETTING - COMPLETE ANALYSIS');
  console.log('='.repeat(70));
  console.log('');
  console.log('Wallet:', WALLET);
  console.log('');
  console.log('Note: RogueTrader uses ROGUEBankroll for payouts.');
  console.log('Bets go TO RogueTrader, winnings come FROM ROGUEBankroll.');
  console.log('');

  // Get all transactions
  console.log('Fetching all transactions...');
  const allTxs = await fetchAll(`${EXPLORER_API}/addresses/${WALLET}/transactions`);

  // Bets placed to RogueTrader
  const bets = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === ROGUETRADER.toLowerCase() &&
    tx.method === 'placeBet'
  );

  let totalBet = 0n;
  for (const tx of bets) {
    totalBet += BigInt(tx.value || '0');
  }

  console.log('');
  console.log('='.repeat(70));
  console.log('BETS PLACED (to RogueTrader)');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total bets:', bets.length);
  console.log('Total wagered:', ethers.formatEther(totalBet), 'ROGUE');
  console.log('Average bet:', ethers.formatEther(totalBet / BigInt(bets.length || 1)), 'ROGUE');

  // Deposits to bankroll (LP deposits, NOT betting)
  const bankrollDeposits = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === ROGUEBANKROLL.toLowerCase() &&
    (tx.method === 'depositROGUE' || tx.method === 'deposit')
  );

  let totalDeposited = 0n;
  for (const tx of bankrollDeposits) {
    totalDeposited += BigInt(tx.value || '0');
  }

  console.log('');
  console.log('='.repeat(70));
  console.log('LP DEPOSITS (to ROGUEBankroll)');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total deposits:', bankrollDeposits.length);
  console.log('Total deposited:', ethers.formatEther(totalDeposited), 'ROGUE');

  // Get internal transactions (winnings from bankroll)
  console.log('');
  console.log('Fetching internal transactions...');
  const allInternal = await fetchAll(`${EXPLORER_API}/addresses/${WALLET}/internal-transactions`);

  // All incoming from bankroll
  const fromBankroll = allInternal.filter(tx =>
    tx.from?.hash?.toLowerCase() === ROGUEBANKROLL.toLowerCase() &&
    tx.to?.hash?.toLowerCase() === WALLET.toLowerCase()
  );

  let totalFromBankroll = 0n;
  for (const tx of fromBankroll) {
    totalFromBankroll += BigInt(tx.value || '0');
  }

  console.log('');
  console.log('='.repeat(70));
  console.log('RECEIVED FROM ROGUEBANKROLL');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total transactions:', fromBankroll.length);
  console.log('Total received:', ethers.formatEther(totalFromBankroll), 'ROGUE');
  console.log('');
  console.log('This includes:');
  console.log('  - Betting winnings (paid via bankroll)');
  console.log('  - LP withdrawal principal');
  console.log('  - LP yield/profits');

  // To get betting-specific P&L, we need to look at bet transactions
  // and check which ones had winning payouts
  console.log('');
  console.log('='.repeat(70));
  console.log('ANALYZING INDIVIDUAL BET OUTCOMES');
  console.log('='.repeat(70));
  console.log('');

  // Sample a few bet transactions to see the pattern
  console.log('Sampling 10 recent bets to analyze payout pattern...');
  console.log('');

  let wins = 0;
  let losses = 0;
  let winAmount = 0n;
  let sampleSize = Math.min(50, bets.length);

  for (let i = 0; i < sampleSize; i++) {
    const bet = bets[i];
    const betValue = BigInt(bet.value || '0');

    // Get internal txs for this specific transaction
    try {
      const txDetail = await fetch(`${EXPLORER_API}/transactions/${bet.hash}/internal-transactions`).then(r => r.json());

      // Look for payout back to the wallet
      let payout = 0n;
      if (txDetail.items) {
        for (const itx of txDetail.items) {
          if (itx.to?.hash?.toLowerCase() === WALLET.toLowerCase()) {
            payout += BigInt(itx.value || '0');
          }
        }
      }

      if (payout > 0n) {
        wins++;
        winAmount += payout;
        if (i < 5) {
          console.log(`Bet ${i + 1}: ${ethers.formatEther(betValue)} ROGUE → WON ${ethers.formatEther(payout)} ROGUE`);
        }
      } else {
        losses++;
        if (i < 5) {
          console.log(`Bet ${i + 1}: ${ethers.formatEther(betValue)} ROGUE → LOST`);
        }
      }
    } catch (err) {
      // Skip failed lookups
    }

    await new Promise(r => setTimeout(r, 100));
  }

  console.log('');
  console.log(`Sample results (${sampleSize} bets):`);
  console.log(`  Wins: ${wins}`);
  console.log(`  Losses: ${losses}`);
  console.log(`  Win rate: ${(wins / sampleSize * 100).toFixed(1)}%`);
  console.log(`  Sample win amount: ${ethers.formatEther(winAmount)} ROGUE`);

  // Extrapolate to full dataset
  const estimatedWinRate = wins / sampleSize;
  const estimatedWins = Math.round(bets.length * estimatedWinRate);
  const avgWinPayout = wins > 0 ? winAmount / BigInt(wins) : 0n;
  const estimatedTotalWinnings = avgWinPayout * BigInt(estimatedWins);

  console.log('');
  console.log('='.repeat(70));
  console.log('ESTIMATED BETTING P&L');
  console.log('='.repeat(70));
  console.log('');
  console.log('Total bets:', bets.length);
  console.log('Total wagered:', ethers.formatEther(totalBet), 'ROGUE');
  console.log('');
  console.log('Estimated wins:', estimatedWins, `(${(estimatedWinRate * 100).toFixed(1)}% win rate)`);
  console.log('Estimated losses:', bets.length - estimatedWins);
  console.log('Average win payout:', ethers.formatEther(avgWinPayout), 'ROGUE');
  console.log('');
  console.log('Estimated total winnings:', ethers.formatEther(estimatedTotalWinnings), 'ROGUE');

  const estimatedPnL = estimatedTotalWinnings - totalBet;
  console.log('');
  console.log(`ESTIMATED NET P&L: ${ethers.formatEther(estimatedPnL)} ROGUE ${estimatedPnL >= 0n ? '✅' : '❌'}`);

  // Overall summary
  console.log('');
  console.log('='.repeat(70));
  console.log('OVERALL ROGUETRADER SUMMARY');
  console.log('='.repeat(70));
  console.log('');
  console.log('BETTING ACTIVITY:');
  console.log(`  Bets placed: ${bets.length}`);
  console.log(`  Total wagered: ${ethers.formatEther(totalBet)} ROGUE`);
  console.log(`  Average bet size: ${ethers.formatEther(totalBet / BigInt(bets.length || 1))} ROGUE`);
  console.log('');
  console.log('LP ACTIVITY:');
  console.log(`  Deposits: ${bankrollDeposits.length} txs, ${ethers.formatEther(totalDeposited)} ROGUE`);
  console.log(`  Received from bankroll: ${fromBankroll.length} txs, ${ethers.formatEther(totalFromBankroll)} ROGUE`);
  console.log(`  Net from bankroll: +${ethers.formatEther(totalFromBankroll - totalDeposited)} ROGUE`);
}

main().catch(console.error);
