const { ethers } = require('ethers');

const EXPLORER_API = 'https://roguescan.io/api/v2';
const ROGUETRADER = '0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A';
const WALLET = '0xA2b101eF9EC4788D12b3352438cc0583dAacBf60'.toLowerCase();

async function main() {
  // Get logs from the RogueTrader contract to see what events it emits
  console.log('Fetching logs from RogueTrader contract...');

  const logs = await fetch(`${EXPLORER_API}/addresses/${ROGUETRADER}/logs`).then(r => r.json());

  console.log('Recent event types:');
  const eventTypes = {};
  for (const log of logs.items || []) {
    const event = log.decoded?.method_call || 'Unknown';
    if (!eventTypes[event]) eventTypes[event] = 0;
    eventTypes[event]++;
  }

  for (const [e, c] of Object.entries(eventTypes).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${e}: ${c}`);
  }

  // Look for a BetSettled event for our wallet
  console.log('');
  console.log('Looking for BetSettled/Settlement events for our wallet...');

  let count = 0;
  for (const log of logs.items || []) {
    const event = log.decoded?.method_call || '';
    if (event.includes('Settled') || event.includes('Resolved') || event.includes('Winner') || event.includes('Payout')) {
      const params = log.decoded?.parameters || [];
      for (const p of params) {
        if (p.value?.toLowerCase() === WALLET) {
          count++;
          console.log('Found settlement for our wallet!');
          console.log(`  Event: ${event}`);
          console.log(`  TX: ${log.transaction_hash}`);
          for (const param of params) {
            console.log(`  ${param.name}: ${param.value}`);
          }
          console.log('');
          if (count >= 5) break;
        }
      }
    }
    if (count >= 5) break;
  }

  if (count === 0) {
    console.log('No settlements found in first page of logs.');
    console.log('');
    console.log('Sample log entries:');
    for (let i = 0; i < Math.min(5, logs.items?.length || 0); i++) {
      const sample = logs.items[i];
      console.log(`  Event: ${sample.decoded?.method_call}`);
      for (const p of sample.decoded?.parameters || []) {
        console.log(`    ${p.name}: ${p.value}`);
      }
      console.log('');
    }
  }

  // Check ROGUEBankroll logs for RogueTraderWinningPayout events
  console.log('='.repeat(50));
  console.log('Checking ROGUEBankroll for RogueTraderWinningPayout events...');
  console.log('');

  const bankrollLogs = await fetch(`${EXPLORER_API}/addresses/0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd/logs`).then(r => r.json());

  const bankrollEventTypes = {};
  for (const log of bankrollLogs.items || []) {
    const event = log.decoded?.method_call || 'Unknown';
    if (!bankrollEventTypes[event]) bankrollEventTypes[event] = 0;
    bankrollEventTypes[event]++;
  }

  console.log('ROGUEBankroll event types:');
  for (const [e, c] of Object.entries(bankrollEventTypes).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${e}: ${c}`);
  }

  // Look for payout events
  console.log('');
  console.log('Looking for payout events to our wallet...');

  count = 0;
  for (const log of bankrollLogs.items || []) {
    const event = log.decoded?.method_call || '';
    if (event.includes('Payout') || event.includes('Winner') || event.includes('RogueTrader')) {
      const params = log.decoded?.parameters || [];
      for (const p of params) {
        if (p.value?.toLowerCase() === WALLET) {
          count++;
          console.log('Found payout to our wallet!');
          console.log(`  Event: ${event}`);
          console.log(`  TX: ${log.transaction_hash}`);
          for (const param of params) {
            console.log(`  ${param.name}: ${param.value}`);
          }
          console.log('');
          if (count >= 5) break;
        }
      }
    }
    if (count >= 5) break;
  }
}

main().catch(console.error);
