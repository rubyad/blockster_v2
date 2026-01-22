/**
 * Check a tournament win transaction to see where the money comes from
 */

const { ethers } = require('ethers');

const WALLET_ADDRESS = '0x26d3b4647D9793ae1B05Af96c1ac08e722270834';
const TOURNAMENT_CONTRACT = '0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058';
const EXPLORER_API = 'https://roguescan.io/api/v2';

async function main() {
  // Check the win TX: 0x1a09b63b7a1ad2407a0880d8e46f670ffdc0674d2217b5acda2ea5cca097bf71
  const winTxHash = '0x1a09b63b7a1ad2407a0880d8e46f670ffdc0674d2217b5acda2ea5cca097bf71';

  console.log('=== CHECKING WIN TRANSACTION ===');
  console.log('TX:', winTxHash);
  console.log('');

  // Get transaction details
  const txResponse = await fetch(`${EXPLORER_API}/transactions/${winTxHash}`);
  const tx = await txResponse.json();

  console.log('From:', tx.from?.hash);
  console.log('To:', tx.to?.hash);
  console.log('Value:', ethers.formatEther(tx.value || '0'), 'ROGUE');
  console.log('Method:', tx.method);
  console.log('');

  // Get internal transactions
  const internalResponse = await fetch(`${EXPLORER_API}/transactions/${winTxHash}/internal-transactions`);
  const internal = await internalResponse.json();

  console.log('=== INTERNAL TRANSACTIONS ===');
  if (internal.items) {
    internal.items.forEach((itx, i) => {
      console.log(`Internal TX ${i + 1}:`);
      console.log('  From:', itx.from?.hash);
      console.log('  To:', itx.to?.hash);
      console.log('  Value:', ethers.formatEther(itx.value || '0'), 'ROGUE');
      console.log('');
    });
  }

  // This TX hash is actually when ANOTHER player registered and our wallet won
  // Let's find a TX where our wallet registered and also won
  console.log('');
  console.log('=== CHECKING WHO INITIATED THE WIN TX ===');
  console.log('TX initiator (from):', tx.from?.hash);
  console.log('Is this our wallet?', tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase());

  if (tx.from?.hash?.toLowerCase() !== WALLET_ADDRESS.toLowerCase()) {
    console.log('');
    console.log('IMPORTANT: This TX was NOT initiated by our wallet!');
    console.log('Another player registered, and that triggered a payout to our wallet.');
    console.log('');
    console.log('This means tournament winnings come from OTHER players registerPlayerInSitGoROGUETournament calls,');
    console.log('not from our own transactions. This is why they appear as internal transactions TO us.');
  }

  // Let's verify by checking the tournament contract balance
  console.log('');
  console.log('=== TOURNAMENT MECHANICS ===');
  console.log('1. Player A registers with 1M ROGUE');
  console.log('2. Player B registers with 1M ROGUE');
  console.log('3. Tournament completes, contract sends prize to winner');
  console.log('4. Winner receives ~2M ROGUE as internal tx from contracts action');
  console.log('');
  console.log('The internal txs TO our wallet are payouts when we WIN.');
  console.log('They are triggered by OTHER players transactions, not ours.');
}

main().catch(console.error);
