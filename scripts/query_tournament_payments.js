const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const TOURNAMENT_CONTRACT = '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058';
const RPC_URL = 'https://rpc.roguechain.io/rpc';

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  console.log('=== QUERYING TOURNAMENT CONTRACT FOR PAYMENTS ===');
  console.log('Wallet:', WALLET_ADDRESS);
  console.log('Tournament Contract:', TOURNAMENT_CONTRACT);
  console.log('');

  // First, let's get the contract code to see what events it emits
  const code = await provider.getCode(TOURNAMENT_CONTRACT);
  console.log('Contract has code:', code.length > 2 ? 'Yes' : 'No');
  console.log('');

  // Common event signatures for tournament/prize payouts
  const possibleEvents = [
    'Transfer(address,address,uint256)',
    'PrizePaid(address,uint256)',
    'TournamentWon(address,uint256)',
    'PlayerPaid(address,uint256)',
    'Withdrawal(address,uint256)',
    'RewardPaid(address,uint256)',
    'WinnerPaid(address,uint256,uint256)',
    'PrizeDistributed(address,uint256)',
  ];

  console.log('Scanning for common payout events...');
  console.log('');

  // Get all logs from tournament contract
  const currentBlock = await provider.getBlockNumber();
  console.log('Current block:', currentBlock);

  // Scan in chunks
  const CHUNK_SIZE = 50000;
  let allLogs = [];

  // Try to get all logs from this contract where wallet is involved
  // We'll look for any log that contains the wallet address

  const walletPadded = ethers.zeroPadValue(WALLET_ADDRESS, 32).toLowerCase();

  console.log('Scanning for logs with wallet address in topics...');

  for (let fromBlock = 0; fromBlock < currentBlock; fromBlock += CHUNK_SIZE) {
    const toBlock = Math.min(fromBlock + CHUNK_SIZE - 1, currentBlock);

    try {
      // Get logs from tournament contract with wallet in any topic position
      const logs = await provider.getLogs({
        address: TOURNAMENT_CONTRACT,
        fromBlock,
        toBlock,
        topics: [
          null, // any event
          null, // topic1 - could be wallet
          null, // topic2 - could be wallet
        ]
      });

      // Filter to only logs mentioning our wallet
      const relevantLogs = logs.filter(log => {
        return log.topics.some(t => t && t.toLowerCase() === walletPadded) ||
               (log.data && log.data.toLowerCase().includes(WALLET_ADDRESS.toLowerCase().slice(2)));
      });

      if (relevantLogs.length > 0) {
        allLogs = allLogs.concat(relevantLogs);
        process.stdout.write(`\rBlocks ${fromBlock}-${toBlock}: Found ${allLogs.length} relevant logs...`);
      }
    } catch (err) {
      if (err.message.includes('Log response size exceeded')) {
        // Try smaller chunks
        console.log(`\nChunk too large at ${fromBlock}, trying smaller...`);
      }
    }
  }

  console.log(`\n\nTotal relevant logs found: ${allLogs.length}`);

  // Analyze the logs
  console.log('\n=== ANALYZING LOGS ===');

  // Group by event signature
  const eventGroups = {};
  allLogs.forEach(log => {
    const sig = log.topics[0];
    if (!eventGroups[sig]) {
      eventGroups[sig] = [];
    }
    eventGroups[sig].push(log);
  });

  console.log('\nEvent signatures found:');
  Object.keys(eventGroups).forEach(sig => {
    console.log(`  ${sig}: ${eventGroups[sig].length} logs`);
  });

  // Try to decode Transfer events
  const transferSig = ethers.id('Transfer(address,address,uint256)');
  const transferLogs = allLogs.filter(l => l.topics[0] === transferSig);

  console.log(`\n\nTransfer events: ${transferLogs.length}`);

  // Calculate total received via Transfer events
  let totalReceived = 0n;
  let totalSent = 0n;

  transferLogs.forEach(log => {
    const from = '0x' + log.topics[1].slice(26);
    const to = '0x' + log.topics[2].slice(26);
    const value = BigInt(log.data);

    if (to.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      totalReceived += value;
    }
    if (from.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      totalSent += value;
    }
  });

  console.log('Total received via Transfer:', ethers.formatEther(totalReceived), 'ROGUE');
  console.log('Total sent via Transfer:', ethers.formatEther(totalSent), 'ROGUE');

  // Also check for native ROGUE transfers (internal transactions)
  // These don't emit events, so we need to trace
  console.log('\n=== CHECKING FOR NATIVE ROGUE PAYMENTS ===');
  console.log('Native ROGUE transfers dont emit events.');
  console.log('They are internal transactions from contract calls.');
  console.log('');

  // Let's try trace_filter if available
  try {
    console.log('Trying trace_filter API...');
    const traces = await provider.send('trace_filter', [{
      fromAddress: [TOURNAMENT_CONTRACT],
      toAddress: [WALLET_ADDRESS],
      fromBlock: '0x0',
      toBlock: 'latest',
    }]);

    console.log(`Found ${traces.length} traces from tournament to wallet`);

    let traceTotal = 0n;
    traces.forEach(trace => {
      if (trace.action && trace.action.value) {
        traceTotal += BigInt(trace.action.value);
      }
    });

    console.log('Total via traces:', ethers.formatEther(traceTotal), 'ROGUE');
  } catch (err) {
    console.log('trace_filter not available:', err.message);
  }

  // Alternative: try debug_traceBlockByNumber on some blocks
  console.log('\nTrying alternative: check specific tournament win transactions...');
}

main().catch(console.error);
