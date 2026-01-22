const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const EXPLORER_API = 'https://roguescan.io/api/v2';

// Known contract addresses
const KNOWN_CONTRACTS = {
  '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058': 'Tournament (Sit-Go)',
  '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd': 'ROGUEBankroll',
  '0x202aA9C1238E635E4a214d1e600179A1496404CE': 'Bridge',
  '0xBD7593ba68a8363c173c098B6Fac29DF52966eb5': 'Unknown Contract',
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

async function main() {
  console.log('=== SEARCHING FOR MISSING FUND SOURCES ===');
  console.log('');
  console.log('Known discrepancy: ~388M ROGUE');
  console.log('');

  // 1. Check if there are any token transfers we might have missed as ROGUE transfers
  console.log('=== CHECKING TOKEN TRANSFERS ===');
  const tokenTxs = await fetchWithRetry(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/token-transfers?type=ERC-20`);
  console.log(`Total token transfers: ${tokenTxs.items?.length || 0}`);

  if (tokenTxs.items) {
    const rogueTransfers = tokenTxs.items.filter(tx =>
      tx.token?.symbol === 'ROGUE' || tx.token?.name?.includes('ROGUE')
    );
    console.log(`ROGUE token transfers: ${rogueTransfers.length}`);

    // Sum up any ROGUE token transfers (wrapped ROGUE?)
    let tokenRogueIn = 0n;
    for (const tx of tokenTxs.items) {
      if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
        console.log(`  Received: ${tx.total?.value} ${tx.token?.symbol} from ${tx.from?.hash?.slice(0, 10)}...`);
        if (tx.token?.symbol === 'ROGUE') {
          tokenRogueIn += BigInt(tx.total?.value || '0');
        }
      }
    }
  }

  // 2. Check for any logs/events that might indicate rewards or airdrops
  console.log('');
  console.log('=== CHECKING FOR REWARD/AIRDROP EVENTS ===');

  // Look at the contracts that sent to this wallet
  console.log('');
  console.log('Checking unknown contract 0xBD7593...');
  const unknownContract = await fetchWithRetry(`${EXPLORER_API}/addresses/0xBD7593ba68a8363c173c098B6Fac29DF52966eb5`);
  console.log('Contract name:', unknownContract.name || 'Unknown');
  console.log('Contract type:', unknownContract.is_contract ? 'Contract' : 'EOA');

  // 3. Let's look at the timeline of when the wallet had enough ROGUE
  console.log('');
  console.log('=== TIMELINE ANALYSIS ===');
  console.log('Looking at bankroll deposit timing vs funding...');

  // Get bankroll deposit transactions
  const allTxs = [];
  let nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allTxs.push(...data.items);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 50));
  }

  // Find bankroll deposits
  const bankrollDeposits = allTxs
    .filter(tx => tx.to?.hash?.toLowerCase() === '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd'.toLowerCase())
    .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

  console.log(`Total bankroll deposits: ${bankrollDeposits.length}`);

  // Get tournament wins timeline
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
    await new Promise(r => setTimeout(r, 50));
  }

  const tournamentWins = allInternal
    .filter(tx => tx.from?.hash?.toLowerCase() === '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058'.toLowerCase())
    .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

  console.log(`Total tournament wins: ${tournamentWins.length}`);

  // Calculate cumulative balances
  console.log('');
  console.log('=== CUMULATIVE BALANCE SIMULATION ===');

  // Combine all transactions with timestamps
  const allEvents = [];

  // Direct incoming
  const directIn = allTxs.filter(tx =>
    tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );
  for (const tx of directIn) {
    allEvents.push({
      time: new Date(tx.timestamp),
      type: 'direct_in',
      amount: BigInt(tx.value || '0'),
      from: tx.from?.hash
    });
  }

  // Internal incoming
  for (const tx of allInternal) {
    if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      allEvents.push({
        time: new Date(tx.timestamp),
        type: 'internal_in',
        amount: BigInt(tx.value || '0'),
        from: tx.from?.hash
      });
    }
  }

  // Direct outgoing
  const directOut = allTxs.filter(tx =>
    tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()
  );
  for (const tx of directOut) {
    allEvents.push({
      time: new Date(tx.timestamp),
      type: 'direct_out',
      amount: -BigInt(tx.value || '0'),
      to: tx.to?.hash
    });
  }

  // Sort by time
  allEvents.sort((a, b) => a.time - b.time);

  // Simulate balance and find when it goes negative
  let balance = 0n;
  let firstNegative = null;
  let maxNegative = 0n;

  for (const event of allEvents) {
    balance += event.amount;
    if (balance < maxNegative) {
      maxNegative = balance;
      if (!firstNegative) {
        firstNegative = {
          time: event.time,
          balance: balance,
          event: event
        };
      }
    }
  }

  console.log(`First negative balance: ${firstNegative ? firstNegative.time.toISOString() : 'Never'}`);
  console.log(`Maximum negative: ${ethers.formatEther(maxNegative)} ROGUE`);
  console.log('');

  if (firstNegative) {
    console.log('=== FIRST NEGATIVE EVENT ===');
    console.log(`Time: ${firstNegative.time.toISOString()}`);
    console.log(`Balance: ${ethers.formatEther(firstNegative.balance)} ROGUE`);
    console.log(`Event: ${firstNegative.event.type} ${ethers.formatEther(firstNegative.event.amount)} ROGUE`);
  }

  // The maximum negative is approximately the missing funds
  console.log('');
  console.log('=== CONCLUSION ===');
  console.log(`The simulation shows the wallet would go ${ethers.formatEther(-maxNegative)} ROGUE negative.`);
  console.log('This is approximately the missing ~388M ROGUE.');
  console.log('');
  console.log('POSSIBLE EXPLANATIONS:');
  console.log('1. The Roguescan API internal-transactions endpoint is incomplete');
  console.log('2. There are internal txs from other contracts we did not query');
  console.log('3. The tournament contract has a refund/rebate mechanism not captured');
  console.log('4. ROGUE was pre-allocated or airdropped through a mechanism not visible in txs');
}

main().catch(console.error);
