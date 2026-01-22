const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const RPC_URL = 'https://rpc.roguechain.io/rpc';
const EXPLORER_API = 'https://roguescan.io/api/v2';

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  console.log('=== GENESIS ALLOCATION CHECK ===');
  console.log('Wallet:', WALLET_ADDRESS);
  console.log('');

  // Check balance at very early blocks
  const blocksToCheck = [0, 1, 10, 100, 1000, 10000, 100000];

  console.log('Checking balance at historical blocks...');
  console.log('');

  for (const blockNum of blocksToCheck) {
    try {
      const balance = await provider.getBalance(WALLET_ADDRESS, blockNum);
      console.log(`Block ${blockNum}: ${ethers.formatEther(balance)} ROGUE`);
    } catch (err) {
      console.log(`Block ${blockNum}: Error - ${err.message.slice(0, 50)}...`);
    }
  }

  // Get the first transaction to this wallet
  console.log('');
  console.log('=== FIRST TRANSACTIONS TO WALLET ===');

  const response = await fetch(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}/transactions?sort=asc`);
  const data = await response.json();

  if (data.items && data.items.length > 0) {
    console.log('Earliest transactions:');
    for (let i = 0; i < Math.min(5, data.items.length); i++) {
      const tx = data.items[i];
      const direction = tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase() ? 'IN' : 'OUT';
      console.log(`  ${tx.timestamp}: ${direction} - ${ethers.formatEther(tx.value || '0')} ROGUE`);
      console.log(`    Block: ${tx.block}, Hash: ${tx.hash?.slice(0, 20)}...`);
    }
  }

  // Check block 0 genesis
  console.log('');
  console.log('=== GENESIS BLOCK INFO ===');
  try {
    const genesisBlock = await provider.getBlock(0);
    console.log('Genesis block hash:', genesisBlock.hash);
    console.log('Genesis timestamp:', new Date(genesisBlock.timestamp * 1000).toISOString());
    console.log('');

    // Get balance right after first tx
    if (data.items && data.items.length > 0) {
      const firstTxBlock = data.items[0].block;
      const balanceBefore = await provider.getBalance(WALLET_ADDRESS, firstTxBlock - 1);
      console.log(`Balance at block ${firstTxBlock - 1} (before first tx): ${ethers.formatEther(balanceBefore)} ROGUE`);
    }
  } catch (err) {
    console.log('Error getting genesis info:', err.message);
  }

  // Summary
  console.log('');
  console.log('=== SUMMARY ===');
  console.log('');
  console.log('KNOWN INCOMING SOURCES:');
  console.log('1. Direct transfers: 7,502,276 ROGUE (6 txs)');
  console.log('2. Tournament wins: 4,019,341,000 ROGUE (6,631 internal txs)');
  console.log('3. Bankroll withdrawals: 143,015,320 ROGUE (18 internal txs)');
  console.log('4. Bridge: 9,609,326 ROGUE (3 internal txs)');
  console.log('5. Other: 1,099 ROGUE (1 internal tx)');
  console.log('');
  console.log('TOTAL KNOWN INCOMING: ~4,179,469,021 ROGUE');
  console.log('');
  console.log('KNOWN OUTGOING:');
  console.log('1. Tournament entries: ~4,034,080,000 ROGUE');
  console.log('2. Bankroll deposits: ~489,218,948 ROGUE');
  console.log('3. Other sends: ~43,711,067 ROGUE');
  console.log('');
  console.log('TOTAL KNOWN OUTGOING: ~4,567,010,015 ROGUE');
  console.log('');
  console.log('CURRENT BALANCE: 6,725 ROGUE');
  console.log('');
  console.log('EQUATION CHECK:');
  console.log('  Starting + In - Out = Current');
  console.log('  Starting + 4,179,469,021 - 4,567,010,015 = 6,725');
  console.log('  Starting = 6,725 - 4,179,469,021 + 4,567,010,015');
  console.log('  Starting = 387,547,719 ROGUE');
  console.log('');
  console.log('CONCLUSION:');
  console.log('The wallet must have started with ~388M ROGUE from:');
  console.log('- Genesis allocation, OR');
  console.log('- Missing transactions not captured by the API');
}

main().catch(console.error);
