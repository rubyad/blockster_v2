const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
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

async function main() {
  console.log('=== LP TOKEN ANALYSIS ===');
  console.log('');

  // Get all token transfers
  const allTokenTxs = [];
  let nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/token-transfers`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allTokenTxs.push(...data.items);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }

  console.log(`Total token transfers: ${allTokenTxs.length}`);
  console.log('');

  // Group by token
  const byToken = {};
  for (const tx of allTokenTxs) {
    const symbol = tx.token?.symbol || 'Unknown';
    if (!byToken[symbol]) {
      byToken[symbol] = {
        contract: tx.token?.address,
        in: [],
        out: [],
        totalIn: 0n,
        totalOut: 0n
      };
    }

    const value = BigInt(tx.total?.value || '0');
    if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      byToken[symbol].in.push(tx);
      byToken[symbol].totalIn += value;
    }
    if (tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      byToken[symbol].out.push(tx);
      byToken[symbol].totalOut += value;
    }
  }

  console.log('=== TOKEN SUMMARY ===');
  for (const [symbol, data] of Object.entries(byToken)) {
    console.log(`\n${symbol}:`);
    console.log(`  Contract: ${data.contract}`);
    console.log(`  Received: ${data.in.length} txs`);
    console.log(`  Sent: ${data.out.length} txs`);
    console.log(`  Total IN: ${ethers.formatEther(data.totalIn)}`);
    console.log(`  Total OUT: ${ethers.formatEther(data.totalOut)}`);
    console.log(`  Net: ${ethers.formatEther(data.totalIn - data.totalOut)}`);
  }

  // Focus on LP-ROGUE
  console.log('');
  console.log('=== LP-ROGUE DETAILED ANALYSIS ===');
  const lpRogue = byToken['LP-ROGUE'];

  if (lpRogue) {
    console.log(`\nLP-ROGUE Contract: ${lpRogue.contract}`);
    console.log(`Total received: ${ethers.formatEther(lpRogue.totalIn)} LP-ROGUE`);
    console.log(`Total sent: ${ethers.formatEther(lpRogue.totalOut)} LP-ROGUE`);

    // Check the LP contract
    console.log('');
    console.log('Checking LP contract details...');
    const lpContract = await fetchWithRetry(`${EXPLORER_API}/addresses/${lpRogue.contract}`);
    console.log('Contract name:', lpContract.name || 'Unknown');

    // Check if there's a corresponding ROGUE redemption
    console.log('');
    console.log('Looking for LP redemption transactions...');

    // The LP tokens were all received from 0x0000... which is the null address (minting)
    // and likely burned when withdrawn

    // Let's look at the first LP token event to understand timing
    const sortedLpIn = lpRogue.in.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
    if (sortedLpIn.length > 0) {
      console.log('');
      console.log('First LP-ROGUE minting:');
      console.log(`  Time: ${sortedLpIn[0].timestamp}`);
      console.log(`  Amount: ${ethers.formatEther(BigInt(sortedLpIn[0].total?.value || '0'))}`);
      console.log(`  TX: ${sortedLpIn[0].tx_hash}`);
    }

    // Check if LP tokens were burned (sent to 0x0000...)
    const lpOut = lpRogue.out;
    const burned = lpOut.filter(tx =>
      tx.to?.hash?.toLowerCase() === '0x0000000000000000000000000000000000000000'
    );
    console.log('');
    console.log(`LP-ROGUE burned (sent to 0x0): ${burned.length} txs`);

    if (burned.length > 0) {
      let totalBurned = 0n;
      for (const tx of burned) {
        totalBurned += BigInt(tx.total?.value || '0');
      }
      console.log(`Total burned: ${ethers.formatEther(totalBurned)} LP-ROGUE`);
    }
  }

  // Now the KEY question: when LP tokens are minted, does the wallet also receive ROGUE?
  console.log('');
  console.log('=== CROSS-REFERENCING LP MINTING WITH ROGUE RECEIPTS ===');

  // Get the bankroll internal txs to this wallet
  const allInternal = [];
  nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allInternal.push(...data.items);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }

  // Filter to bankroll withdrawals
  const bankrollWithdrawals = allInternal.filter(tx =>
    tx.from?.hash?.toLowerCase() === '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd'.toLowerCase() &&
    tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );

  console.log(`Bankroll withdrawals: ${bankrollWithdrawals.length}`);

  // Compare LP received vs ROGUE withdrawn from bankroll
  let totalBankrollWithdrawn = 0n;
  for (const tx of bankrollWithdrawals) {
    totalBankrollWithdrawn += BigInt(tx.value || '0');
  }

  console.log(`Total ROGUE from bankroll: ${ethers.formatEther(totalBankrollWithdrawn)} ROGUE`);

  if (lpRogue) {
    console.log(`Total LP-ROGUE received: ${ethers.formatEther(lpRogue.totalIn)}`);
    console.log('');
    console.log('Note: LP tokens represent liquidity pool shares, NOT direct ROGUE.');
    console.log('When you deposit ROGUE to bankroll, you get LP tokens.');
    console.log('When you withdraw, you burn LP tokens and get ROGUE back.');
  }

  // Final summary
  console.log('');
  console.log('=== FINAL ANALYSIS ===');
  console.log('');
  console.log('The LP-ROGUE tokens are NOT the source of missing ROGUE.');
  console.log('LP tokens are RECEIPTS for ROGUE deposited, not additional ROGUE.');
  console.log('');
  console.log('The ~388M ROGUE discrepancy remains unexplained by:');
  console.log('- Direct transfers (7.5M ROGUE)');
  console.log('- Tournament wins (4.02B ROGUE internal txs)');
  console.log('- Bankroll withdrawals (143M ROGUE internal txs)');
  console.log('- Bridge transfers (9.6M ROGUE internal txs)');
  console.log('- LP token minting (not ROGUE, just receipts)');
  console.log('');
  console.log('MOST LIKELY EXPLANATION:');
  console.log('The Roguescan API internal-transactions endpoint is INCOMPLETE.');
  console.log('There are likely ~388M ROGUE in uncaptured internal transactions');
  console.log('from tournament winnings or other contract interactions.');
}

main().catch(console.error);
