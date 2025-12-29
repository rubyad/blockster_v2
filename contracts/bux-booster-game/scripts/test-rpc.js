/**
 * Test script to check if RPC can handle any transactions
 */

const { ethers } = require("ethers");
require("dotenv").config();

const RPC_URL = "https://rpc.roguechain.io/rpc";
const CHAIN_ID = 560013;

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log("Testing RPC connectivity...\n");

  // Test 1: Get chain ID
  try {
    const network = await provider.getNetwork();
    console.log("✓ Chain ID:", network.chainId.toString());
  } catch (e) {
    console.log("✗ Failed to get chain ID:", e.message);
  }

  // Test 2: Get balance
  try {
    const balance = await provider.getBalance(wallet.address);
    console.log("✓ Balance:", ethers.formatEther(balance), "ROGUE");
  } catch (e) {
    console.log("✗ Failed to get balance:", e.message);
  }

  // Test 3: Get nonce
  try {
    const nonce = await provider.getTransactionCount(wallet.address);
    console.log("✓ Nonce:", nonce);
  } catch (e) {
    console.log("✗ Failed to get nonce:", e.message);
  }

  // Test 4: Get gas price
  try {
    const feeData = await provider.getFeeData();
    console.log("✓ Gas Price:", feeData.gasPrice?.toString() || "N/A");
  } catch (e) {
    console.log("✗ Failed to get gas price:", e.message);
  }

  // Test 5: Estimate gas for simple transfer
  try {
    const gasEstimate = await provider.estimateGas({
      from: wallet.address,
      to: wallet.address,
      value: 0
    });
    console.log("✓ Gas estimate for 0-value transfer:", gasEstimate.toString());
  } catch (e) {
    console.log("✗ Failed to estimate gas:", e.message);
  }

  // Test 6: Try to send a simple 0-value transaction
  console.log("\nTrying to send a simple 0-value transfer...");
  try {
    const tx = await wallet.sendTransaction({
      to: wallet.address,
      value: 0,
      gasLimit: 21000
    });
    console.log("✓ Transaction sent! Hash:", tx.hash);
    console.log("  Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("✓ Transaction confirmed in block:", receipt.blockNumber);
  } catch (e) {
    console.log("✗ Failed to send transaction:", e.message);
    if (e.info) {
      console.log("  Response body:", e.info.responseBody?.substring(0, 200));
    }
  }

  // Test 7: Sign a transaction without sending (check if signing works)
  console.log("\nTrying to sign a transaction (without sending)...");
  try {
    const nonce = await provider.getTransactionCount(wallet.address);
    const tx = {
      to: wallet.address,
      value: 0,
      gasLimit: 21000,
      nonce: nonce,
      chainId: CHAIN_ID,
      gasPrice: 1000000000
    };
    const signedTx = await wallet.signTransaction(tx);
    console.log("✓ Transaction signed successfully");
    console.log("  Raw tx length:", signedTx.length, "chars");

    // Try to broadcast the signed tx
    console.log("\nTrying to broadcast signed transaction...");
    const response = await provider.broadcastTransaction(signedTx);
    console.log("✓ Broadcast successful! Hash:", response.hash);
  } catch (e) {
    console.log("✗ Failed:", e.message);
  }
}

main().catch(console.error);
