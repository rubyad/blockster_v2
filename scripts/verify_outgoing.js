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
  console.log('=== PRECISE OUTGOING VERIFICATION ===');
  console.log('Fetching ALL transactions...');
  console.log('');

  const allTxs = [];
  let nextPageParams = null;
  let page = 0;

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);
      if (!data.items || data.items.length === 0) break;

      allTxs.push(...data.items);
      process.stdout.write(`\rPage ${page}: ${allTxs.length} transactions...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 100));
    } catch (err) {
      console.error(`\nError: ${err.message}`);
      break;
    }
  }

  console.log(`\n\nTotal transactions: ${allTxs.length}`);

  // Separate and sum
  let totalSent = 0n;
  let totalReceived = 0n;
  let gasPaid = 0n;
  const sentTxs = [];
  const receivedTxs = [];

  for (const tx of allTxs) {
    const value = BigInt(tx.value || '0');
    const fee = BigInt(tx.fee?.value || '0');
    const isOutgoing = tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase();

    if (isOutgoing) {
      totalSent += value;
      gasPaid += fee;
      sentTxs.push(tx);
    } else if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      totalReceived += value;
      receivedTxs.push(tx);
    }
  }

  console.log('');
  console.log('=== DIRECT TRANSACTION SUMMARY ===');
  console.log(`Sent: ${sentTxs.length} txs, ${ethers.formatEther(totalSent)} ROGUE`);
  console.log(`Received: ${receivedTxs.length} txs, ${ethers.formatEther(totalReceived)} ROGUE`);
  console.log(`Gas paid: ${ethers.formatEther(gasPaid)} ROGUE`);
  console.log('');

  // Now get internal transactions
  console.log('Fetching internal transactions...');
  const allInternal = [];
  nextPageParams = null;
  page = 0;

  while (true) {
    page++;
    let url = `${EXPLORER_API}/addresses/${WALLET_ADDRESS}/internal-transactions`;
    if (nextPageParams) {
      const params = new URLSearchParams(nextPageParams);
      url += `?${params.toString()}`;
    }

    try {
      const data = await fetchWithRetry(url);
      if (!data.items || data.items.length === 0) break;

      allInternal.push(...data.items);
      process.stdout.write(`\rPage ${page}: ${allInternal.length} internal txs...`);

      if (!data.next_page_params) break;
      nextPageParams = data.next_page_params;

      await new Promise(r => setTimeout(r, 100));
    } catch (err) {
      console.error(`\nError: ${err.message}`);
      break;
    }
  }

  console.log(`\n\nTotal internal transactions: ${allInternal.length}`);

  let internalIn = 0n;
  let internalOut = 0n;

  for (const tx of allInternal) {
    const value = BigInt(tx.value || '0');
    if (tx.to?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      internalIn += value;
    }
    if (tx.from?.hash?.toLowerCase() === WALLET_ADDRESS.toLowerCase()) {
      internalOut += value;
    }
  }

  console.log('');
  console.log('=== INTERNAL TRANSACTION SUMMARY ===');
  console.log(`Internal IN: ${ethers.formatEther(internalIn)} ROGUE`);
  console.log(`Internal OUT: ${ethers.formatEther(internalOut)} ROGUE`);

  // Final calculation
  console.log('');
  console.log('=== COMPLETE FUND FLOW ===');
  console.log('');
  const totalIn = totalReceived + internalIn;
  const totalOut = totalSent + internalOut + gasPaid;

  console.log(`Total IN (direct + internal): ${ethers.formatEther(totalIn)} ROGUE`);
  console.log(`Total OUT (direct + internal + gas): ${ethers.formatEther(totalOut)} ROGUE`);
  console.log(`Net flow: ${ethers.formatEther(totalIn - totalOut)} ROGUE`);
  console.log('');

  // Check current balance
  const currentBalanceResponse = await fetch(`${EXPLORER_API}/addresses/${WALLET_ADDRESS}`);
  const addressData = await currentBalanceResponse.json();
  const currentBalance = BigInt(addressData.coin_balance || '0');

  console.log(`Current balance: ${ethers.formatEther(currentBalance)} ROGUE`);
  console.log('');

  // Calculate implied starting balance
  // Starting + TotalIn - TotalOut = Current
  // Starting = Current - TotalIn + TotalOut
  const impliedStart = currentBalance - totalIn + totalOut;

  console.log('=== ACCOUNTING VERIFICATION ===');
  console.log(`If wallet started at 0:`);
  console.log(`  Expected current = 0 + ${ethers.formatEther(totalIn)} - ${ethers.formatEther(totalOut)}`);
  console.log(`  Expected current = ${ethers.formatEther(totalIn - totalOut)} ROGUE`);
  console.log(`  Actual current = ${ethers.formatEther(currentBalance)} ROGUE`);
  console.log('');
  console.log(`Implied starting balance: ${ethers.formatEther(impliedStart)} ROGUE`);

  if (impliedStart > 0n) {
    console.log('');
    console.log('=== DISCREPANCY ANALYSIS ===');
    console.log(`There is a ${ethers.formatEther(impliedStart)} ROGUE discrepancy.`);
    console.log('');
    console.log('This means either:');
    console.log('1. The API is missing some incoming transactions');
    console.log('2. The API is over-counting outgoing transactions');
    console.log('3. Some transactions are being double-counted');
  }
}

main().catch(console.error);
