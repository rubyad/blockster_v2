# BUX Minter Transaction Queue Implementation

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Add TransactionQueue Class | **COMPLETE** |
| Phase 2 | Create Queue Instances | **COMPLETE** |
| Phase 3 | Update `/mint` Endpoint | **COMPLETE** |
| Phase 4 | Update `/submit-commitment` Endpoint | **COMPLETE** |
| Phase 5 | Update `/settle-bet` Endpoint | **COMPLETE** |
| Phase 6 | Update `/deposit-house-balance` Endpoint | **COMPLETE** |
| Phase 7 | Update `/set-player-referrer` Endpoint | **COMPLETE** |
| Phase 8 | Add `/queue-status` Monitoring Endpoint | **COMPLETE** |
| Phase 9 | Local Testing | PENDING |
| Phase 10 | Deploy to Fly.io | PENDING |
| Phase 11 | Update Documentation | IN PROGRESS |

**Implementation Date**: February 9, 2026

---

## Detailed Implementation Checklist

### Phase 1: Add TransactionQueue Class ✅

#### 1.1 Create the TransactionQueue class
- [x] Add class definition after imports (line ~19)
- [x] Add constructor with wallet, provider, name parameters
- [x] Add queue array and processing flag
- [x] Add nonce tracking properties (currentNonce, nonceInitialized)
- [x] Add retry configuration (maxRetries: 5, baseDelayMs: 100)

#### 1.2 Add nonce management methods
- [x] `initNonce()` - fetch initial nonce from network
- [x] `resyncNonce()` - re-fetch nonce after errors
- [x] `isNonceError(error)` - detect nonce-related errors

#### 1.3 Add queue processing
- [x] `enqueue(txFunction, options)` - add transaction to queue, return Promise
- [x] `processQueue()` - main loop with sequential execution
- [x] Implement exponential backoff retry (100ms, 200ms, 400ms, 800ms, 1600ms)
- [x] `status()` - return queue state for monitoring

### Phase 2: Create Queue Instances ✅

- [x] Create `txQueues` object after wallet initialization (~line 382)
- [x] Create queue for minter wallet (`txQueues.minter`)
- [x] Create queue for settler wallet (`txQueues.settler`)
- [x] Create queue for contract owner wallet (`txQueues.contractOwner`)
- [x] Create queue for referral admin BB wallet (`txQueues.referralBB`)
- [x] Create queue for referral admin RB wallet (`txQueues.referralRB`)
- [x] Add initialization logging for each queue

### Phase 3: Update `/mint` Endpoint ✅

- [x] Check if queue is initialized (return 503 if not)
- [x] Wrap mint transaction in `queue.enqueue()`
- [x] Pass nonce to `contract.mint()` call
- [x] Add logging with nonce value
- [x] Keep existing error handling

### Phase 4: Update `/submit-commitment` Endpoint ✅

- [x] Check if queue is initialized (return 503 if not)
- [x] Wrap submitCommitment in `queue.enqueue()`
- [x] Use `txNonce` variable name to avoid confusion with game `nonce` parameter
- [x] Pass txNonce to contract call
- [x] Keep existing error handling

### Phase 5: Update `/settle-bet` Endpoint ✅

- [x] Check if queue is initialized (return 503 if not)
- [x] Read bet info BEFORE queueing (read calls don't need nonces)
- [x] Determine if ROGUE bet based on token address
- [x] Wrap settlement in `queue.enqueue()`
- [x] Call appropriate function (settleBet vs settleBetROGUE)
- [x] Pass nonce to contract call
- [x] Add BetAlreadySettled error handling (0x05d09e5f)
- [x] Add BetNotFound error handling (0x469bfa91)

### Phase 6: Update `/deposit-house-balance` Endpoint ✅

- [x] Get both minter queue and contract owner queue
- [x] Check both queues are initialized
- [x] Step 1: Mint via minter queue
- [x] Step 2: Approve via contract owner queue
- [x] Step 3: Deposit via contract owner queue
- [x] Return all three transaction hashes in response
- [x] Handle errors appropriately

### Phase 7: Update `/set-player-referrer` Endpoint ✅

- [x] Get both referral queues (BB and RB)
- [x] Check both queues are initialized
- [x] Read existing referrers BEFORE queueing (read operations)
- [x] Execute BB and RB updates in PARALLEL (different wallets = safe)
- [x] Use Promise.all for parallel execution
- [x] Collect results from both queues
- [x] Return combined results

### Phase 8: Add `/queue-status` Monitoring Endpoint ✅

- [x] Create GET `/queue-status` endpoint
- [x] Require API_SECRET authorization
- [x] Return status for all 5 queues
- [x] Include: name, walletAddress, queueLength, processing, currentNonce, nonceInitialized
- [x] Add timestamp to response

### Phase 9: Local Testing ⏳

- [ ] Start local BUX Minter and verify queue initialization logs
- [ ] Test single requests for each endpoint
- [ ] Test concurrent requests (10 simultaneous mints)
- [ ] Verify sequential nonce assignment in logs
- [ ] Test error recovery (external transaction causing nonce mismatch)

### Phase 10: Deploy to Fly.io ⏳

- [ ] Deploy to Fly.io
- [ ] Monitor deployment logs for queue initialization
- [ ] Call `/queue-status` on production
- [ ] Test single mint operation
- [ ] Test single bet flow (commit → place → settle)
- [ ] Monitor for nonce errors in logs

### Phase 11: Update Documentation ⏳

- [ ] Update CLAUDE.md with transaction queue documentation
- [ ] Document the new `/queue-status` endpoint
- [ ] Add troubleshooting guide for queue issues

---

## Problem Statement

The BUX Minter service currently has **no transaction queuing** - all contract calls go directly to the blockchain. When multiple requests arrive concurrently (which happens constantly with thousands of users earning read/share/watch rewards and placing/settling bets), the following occurs:

1. Request A calls `provider.getTransactionCount()` → gets nonce 100
2. Request B calls `provider.getTransactionCount()` → also gets nonce 100 (tx A not mined yet)
3. Both transactions submitted with nonce 100
4. One succeeds, one fails with "nonce too low" error

This is especially problematic because the **settler wallet is shared by ALL users** for:
- `/submit-commitment` - submitting bet commitments
- `/settle-bet` - settling completed bets

And the **minter wallet is shared** for:
- `/mint` - minting BUX for read/share/watch rewards

Under production load with thousands of concurrent users, nonce errors are **guaranteed**.

---

## Solution Architecture

### Core Principles

1. **One queue per wallet** - Each wallet that sends transactions gets its own queue
2. **Local nonce tracking** - Never query the network for nonce during processing; track locally
3. **Sequential processing** - One transaction at a time per wallet
4. **Automatic retry with backoff** - Re-sync nonce and retry on nonce errors
5. **Promise-based API** - Callers await their transaction completion

### Wallets Requiring Queues

| Wallet | Environment Variable | Used By | Queue Name |
|--------|---------------------|---------|------------|
| Minter | `OWNER_PRIVATE_KEY` | `/mint`, `/deposit-house-balance` (mint step) | `txQueues.minter` |
| Settler | `SETTLER_PRIVATE_KEY` | `/submit-commitment`, `/settle-bet` | `txQueues.settler` |
| Contract Owner | `CONTRACT_OWNER_PRIVATE_KEY` | `/deposit-house-balance` (approve, deposit) | `txQueues.contractOwner` |
| Referral Admin BB | `REFERRAL_ADMIN_BB_PRIVATE_KEY` | `/set-player-referrer` (BuxBoosterGame) | `txQueues.referralBB` |
| Referral Admin RB | `REFERRAL_ADMIN_RB_PRIVATE_KEY` | `/set-player-referrer` (ROGUEBankroll) | `txQueues.referralRB` |

---

## Implementation Details

### Code Locations in `bux-minter/index.js`

| Component | Lines | Description |
|-----------|-------|-------------|
| TransactionQueue class | 19-198 | Core queue class with nonce management |
| Queue instances creation | 382-416 | Creates `txQueues` object with all 5 queues |
| `/mint` endpoint (queued) | 111-180 | Uses `txQueues.minter` |
| `/submit-commitment` endpoint (queued) | 418-461 | Uses `txQueues.settler` |
| `/settle-bet` endpoint (queued) | 420-500 | Uses `txQueues.settler` |
| `/deposit-house-balance` endpoint (queued) | 502-568 | Uses `txQueues.minter` + `txQueues.contractOwner` |
| `/set-player-referrer` endpoint (queued) | 676-785 | Uses `txQueues.referralBB` + `txQueues.referralRB` in parallel |
| `/queue-status` endpoint | 787-803 | Monitoring endpoint |

### TransactionQueue Class

The `TransactionQueue` class (lines 19-198) provides:

**Properties:**
- `wallet` - ethers.Wallet instance for signing transactions
- `provider` - ethers.JsonRpcProvider for blockchain interaction
- `name` - String identifier for logging (e.g., "minter", "settler")
- `queue` - Array of pending transaction items
- `processing` - Boolean flag to prevent concurrent processing
- `currentNonce` - Locally tracked nonce (initialized lazily)
- `nonceInitialized` - Whether initial nonce has been fetched
- `maxRetries` - Max retry attempts for nonce errors (default: 5)
- `baseDelayMs` - Base delay for exponential backoff (default: 100ms)

**Methods:**
- `enqueue(txFunction, options)` - Add transaction to queue, returns Promise
- `initNonce()` - Fetch initial nonce from network (called once)
- `resyncNonce()` - Re-fetch nonce after errors
- `isNonceError(error)` - Detect nonce-related errors
- `processQueue()` - Main processing loop (runs sequentially)
- `status()` - Return queue state for monitoring

**Queue Item Structure:**
```javascript
{
  txFunction: async (nonce) => receipt,  // The transaction function
  resolve: Function,                      // Promise resolve
  reject: Function,                       // Promise reject
  retries: 0,                             // Current retry count
  priority: false,                        // Priority flag (front of queue)
  enqueuedAt: Date.now()                  // For latency tracking
}
```

### Nonce Error Detection

The queue automatically detects and retries these nonce-related errors:
- Messages containing: "nonce", "replacement transaction underpriced", "already known", "transaction with same nonce"
- Error codes: `nonce_expired`, `replacement_underpriced`

### Retry Strategy

1. On nonce error, increment retry counter
2. Calculate delay: `baseDelayMs * 2^(retries-1)` (exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms)
3. Re-sync nonce from blockchain
4. Wait for delay
5. Put transaction back at front of queue
6. After 5 retries, reject with error

---

## Endpoint Changes Summary

### `/mint` Endpoint

**Before:**
```javascript
const tx = await contract.mint(walletAddress, amountInWei);
const receipt = await tx.wait();
```

**After:**
```javascript
const queue = txQueues.minter;
if (!queue) {
  return res.status(503).json({ error: 'Transaction queue not initialized' });
}

const receipt = await queue.enqueue(async (nonce) => {
  console.log(`[/mint] Minting ${amount} ${actualToken} to ${walletAddress} with nonce ${nonce}`);
  const tx = await contract.mint(walletAddress, amountInWei, { nonce });
  return await tx.wait();
});
```

### `/submit-commitment` Endpoint

**Key Change:** Uses `txNonce` for transaction nonce to avoid confusion with the game `nonce` parameter:
```javascript
const receipt = await queue.enqueue(async (txNonce) => {
  const tx = await buxBoosterContract.submitCommitment(commitmentHash, player, nonce, { nonce: txNonce });
  return await tx.wait();
});
```

### `/settle-bet` Endpoint

**Key Change:** Reads bet info BEFORE queueing (read calls don't need nonces):
```javascript
// Read bet info BEFORE queueing (this is a read call, no nonce needed)
const bet = await buxBoosterContract.bets(commitmentHash);
const isROGUE = bet.token === "0x0000000000000000000000000000000000000000";

// Execute settlement through queue
const receipt = await queue.enqueue(async (nonce) => {
  const tx = isROGUE
    ? await buxBoosterContract.settleBetROGUE(commitmentHash, serverSeed, results, won, { nonce })
    : await buxBoosterContract.settleBet(commitmentHash, serverSeed, results, won, { nonce });
  return await tx.wait();
});
```

**Added Error Handling:**
```javascript
if (error.message?.includes('0x05d09e5f')) {
  return res.status(400).json({ error: 'BetAlreadySettled', details: 'This bet has already been settled' });
}
if (error.message?.includes('0x469bfa91')) {
  return res.status(400).json({ error: 'BetNotFound', details: 'Bet not found on chain' });
}
```

### `/deposit-house-balance` Endpoint

**Key Change:** Uses TWO queues sequentially:
1. `txQueues.minter` for minting tokens to contract owner
2. `txQueues.contractOwner` for approve and deposit

```javascript
// Step 1: Mint tokens (minter queue)
const mintReceipt = await tokenQueue.enqueue(async (nonce) => {
  const tx = await tokenContract.mint(contractOwnerWallet.address, amountWei, { nonce });
  return await tx.wait();
});

// Step 2: Approve (contract owner queue)
const approveReceipt = await ownerQueue.enqueue(async (nonce) => {
  const tx = await tokenContractWithApprove.approve(BUXBOOSTER_CONTRACT_ADDRESS, amountWei, { nonce });
  return await tx.wait();
});

// Step 3: Deposit (contract owner queue)
const depositReceipt = await ownerQueue.enqueue(async (nonce) => {
  const tx = await buxBoosterFromOwner.depositHouseBalance(tokenAddress, amountWei, { nonce });
  return await tx.wait();
});
```

**Response now includes all three tx hashes:**
```javascript
res.json({
  success: true,
  mintTxHash: mintReceipt.hash,
  approveTxHash: approveReceipt.hash,
  depositTxHash: depositReceipt.hash,
  token,
  amountDeposited: amount,
  newHouseBalance: ethers.formatUnits(config.houseBalance, 18)
});
```

### `/set-player-referrer` Endpoint

**Key Change:** Uses TWO queues in PARALLEL (different wallets = safe to parallelize):
```javascript
// Check if referrers are already set (read operations - no queue needed)
const [bbExistingReferrer, rbExistingReferrer] = await Promise.all([
  buxBoosterReferralContract.playerReferrers(playerAddr),
  rogueBankrollWriteContract.playerReferrers(playerAddr)
]);

// Execute referrer updates in parallel
const promises = [];

if (!bbAlreadySet) {
  promises.push(
    bbQueue.enqueue(async (nonce) => {
      const tx = await buxBoosterReferralContract.setPlayerReferrer(playerAddr, referrerAddr, { nonce });
      return await tx.wait();
    }).then(receipt => {
      results.buxBoosterGame.success = true;
      results.buxBoosterGame.txHash = receipt.hash;
    }).catch(error => {
      results.buxBoosterGame.error = error.message;
    })
  );
}

// Similar for rbQueue...

await Promise.all(promises);
```

---

## Monitoring

### `/queue-status` Endpoint

**Request:**
```bash
curl -H "Authorization: Bearer $API_SECRET" https://bux-minter.fly.dev/queue-status
```

**Response:**
```json
{
  "timestamp": "2026-02-09T12:00:00.000Z",
  "queues": {
    "minter": {
      "name": "minter",
      "walletAddress": "0x...",
      "queueLength": 0,
      "processing": false,
      "currentNonce": 1234,
      "nonceInitialized": true
    },
    "settler": {
      "name": "settler",
      "walletAddress": "0x...",
      "queueLength": 3,
      "processing": true,
      "currentNonce": 5678,
      "nonceInitialized": true
    },
    "contractOwner": { ... },
    "referralBB": { ... },
    "referralRB": { ... }
  }
}
```

### Monitoring Alerts to Set Up

1. **Queue depth alert**: If any queue exceeds 50 items
2. **Nonce error alert**: If nonce errors occur after implementation (shouldn't happen)
3. **Response time alert**: If `/settle-bet` > 10s or `/mint` > 5s
4. **Processing stuck alert**: If `processing: true` but `queueLength: 0` for > 30s

---

## Performance Considerations

### Throughput Limits

With sequential processing per wallet:
- **Block time**: Rogue Chain ~250ms (very fast!)
- **Max throughput per wallet**: ~200+ tx/minute (limited by RPC and confirmation time)
- **With 5 wallets**: ~1000+ tx/minute total theoretical max

### Latency Impact

The queue adds minimal latency:
- First transaction: ~0ms (queue is empty)
- Subsequent transactions: ~50ms inter-transaction delay + confirmation time of previous tx
- Under load: Latency scales with queue depth

### Scaling Options (if needed)

1. **Multiple Minter Wallets**: Pool of minter wallets with round-robin selection
2. **Batch Minting**: Contract function to mint to multiple addresses in one tx
3. **Async Rewards**: Queue read rewards in database, process in background batches

---

## Rollback Plan

### If Issues Occur in Production

1. **Check queue status**: `curl /queue-status` - is queue backing up?
2. **Quick fix**: Set `BYPASS_QUEUE=true` in Fly secrets
3. **Rollback**: `flyctl releases list` then `flyctl releases rollback`

### Adding Queue Bypass (Future Enhancement)

```javascript
const BYPASS_QUEUE = process.env.BYPASS_QUEUE === 'true';

if (BYPASS_QUEUE) {
  // Direct call (old behavior)
  const tx = await contract.mint(address, amount);
  const receipt = await tx.wait();
} else {
  // Queued call (new behavior)
  const receipt = await queue.enqueue(async (nonce) => { ... });
}
```

---

## Testing Checklist

### Phase 9: Local Testing

#### 9.1 Start local BUX Minter
- [ ] `cd bux-minter`
- [ ] Ensure `.env` has all required keys
- [ ] `node index.js`
- [ ] Verify startup logs show queue creation:
  ```
  [INIT] Transaction queue created for minter wallet: 0x...
  [INIT] Transaction queue created for settler wallet: 0x...
  [INIT] Transaction queue created for contract owner wallet: 0x...
  [INIT] Transaction queue created for referral admin BB wallet: 0x...
  [INIT] Transaction queue created for referral admin RB wallet: 0x...
  ```

#### 9.2 Test single requests
- [ ] Test `/mint` with single request
- [ ] Test `/submit-commitment` with single request
- [ ] Test `/settle-bet` with single request
- [ ] Test `/queue-status` endpoint
- [ ] Verify all return success

#### 9.3 Test concurrent requests
```bash
#!/bin/bash
# test-concurrent.sh
for i in {1..10}; do
  curl -s -X POST http://localhost:3001/mint \
    -H "Authorization: Bearer $API_SECRET" \
    -H "Content-Type: application/json" \
    -d '{"walletAddress":"0xTestWallet","amount":1,"userId":1}' &
done
wait
echo "Done"
```
- [ ] Run test script
- [ ] Verify all 10 requests succeed
- [ ] Check logs for sequential nonces (0, 1, 2, ...)
- [ ] Check `/queue-status` during test

#### 9.4 Test error recovery
- [ ] Manually send a transaction from settler wallet outside the queue
- [ ] Immediately call `/settle-bet`
- [ ] Verify it recovers (re-syncs nonce and retries)
- [ ] Check logs for: `[TxQueue:settler] Nonce error, retry 1/5...`

### Phase 10: Deployment

#### 10.1 Pre-deployment
- [ ] All local tests passing
- [ ] No console errors during normal operation
- [ ] Queue status endpoint working

#### 10.2 Deploy to Fly.io
```bash
cd bux-minter
flyctl deploy
```
- [ ] Monitor deployment logs for queue initialization messages

#### 10.3 Post-deployment verification
- [ ] Call `/queue-status` on production
- [ ] Test a single mint operation
- [ ] Test a single bet flow (commit → place → settle)
- [ ] Monitor for any nonce errors in logs

---

## Summary

This implementation ensures:

1. **Zero nonce conflicts** - Each wallet processes one transaction at a time
2. **Automatic recovery** - Nonce errors trigger re-sync and retry with exponential backoff
3. **Monitoring** - Queue status endpoint for operational visibility
4. **Parallel where safe** - Referral updates use parallel queues (different wallets)
5. **Sequential where needed** - Deposit flow uses sequential queues (same wallet dependencies)

The queue adds minimal latency (~50ms between transactions) but eliminates the nonce conflict errors seen under concurrent load.
