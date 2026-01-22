const { ethers } = require('ethers');
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
  console.log('Searching for the 591.7M ROGUE transfer to 0x3E5884fe...');
  console.log('');

  // Fetch all internal transactions
  let allInternal = [];
  let nextPageParams = null;

  while (true) {
    let url = `${EXPLORER_API}/addresses/0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    const data = await fetchWithRetry(url);
    if (!data.items || data.items.length === 0) break;
    allInternal.push(...data.items);
    process.stdout.write(`\rFetched ${allInternal.length} internal txs...`);
    if (!data.next_page_params) break;
    nextPageParams = data.next_page_params;
    await new Promise(r => setTimeout(r, 100));
  }

  console.log('');
  console.log('Total internal transactions:', allInternal.length);
  console.log('');

  // Find the big one (>500M)
  console.log('Looking for transfers >500M ROGUE...');
  console.log('');

  for (const tx of allInternal) {
    const value = BigInt(tx.value || '0');
    if (value > 500000000n * 10n**18n &&
        tx.to?.hash?.toLowerCase() === '0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A'.toLowerCase()) {
      console.log('FOUND LARGE TRANSFER:');
      console.log('  From:', tx.from?.hash);
      console.log('  Value:', ethers.formatEther(value), 'ROGUE');
      console.log('  TX Hash:', tx.transaction_hash);
      console.log('  Timestamp:', tx.timestamp);

      // Get info about the source contract
      if (tx.from?.hash) {
        const info = await fetchWithRetry(`${EXPLORER_API}/addresses/${tx.from.hash}`);
        console.log('');
        console.log('SOURCE CONTRACT INFO:');
        console.log('  Name:', info.name || 'Unknown');
        console.log('  Type:', info.is_contract ? 'Contract' : 'EOA');
        console.log('  Balance:', ethers.formatEther(info.coin_balance || '0'), 'ROGUE');
        console.log('  Creator:', info.creator_address_hash);
        if (info.implementations && info.implementations.length > 0) {
          console.log('  Implementations:');
          for (const impl of info.implementations) {
            console.log(`    - ${impl.name}: ${impl.address}`);
          }
        }

        // Get the source contract's transactions to understand where IT got the ROGUE
        console.log('');
        console.log('Checking where the source contract got its ROGUE...');
        const sourceTxs = await fetchWithRetry(`${EXPLORER_API}/addresses/${tx.from.hash}/internal-transactions?sort=asc`);
        if (sourceTxs.items && sourceTxs.items.length > 0) {
          console.log('First 5 incoming internal txs:');
          let count = 0;
          for (const stx of sourceTxs.items) {
            if (stx.to?.hash?.toLowerCase() === tx.from.hash.toLowerCase() && BigInt(stx.value || '0') > 0n) {
              console.log(`  ${stx.timestamp}: ${ethers.formatEther(stx.value)} ROGUE from ${stx.from?.hash?.slice(0,10)}...`);
              count++;
              if (count >= 5) break;
            }
          }
        }
      }
      break;
    }
  }

  // Also show all large transfers for context
  console.log('');
  console.log('All transfers >10M ROGUE received:');
  for (const tx of allInternal) {
    const value = BigInt(tx.value || '0');
    if (value > 10000000n * 10n**18n &&
        tx.to?.hash?.toLowerCase() === '0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A'.toLowerCase()) {
      console.log(`  ${ethers.formatEther(value)} ROGUE from ${tx.from?.hash?.slice(0,10)}...`);
    }
  }
}

main().catch(console.error);
