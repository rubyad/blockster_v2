# RPC Batching Plan

## STATUS: IMPLEMENTATION COMPLETE (March 2026)

All 4 phases implemented. NFTRewarder V6 deployed on Rogue Chain.

- **NFTRewarder V6 Impl**: `0xC2Fb3A92C785aF4DB22D58FD8714C43B3063F3B1`
- **Upgrade tx**: `0xed2b7aeeca1e02610d042b4f2d7abb206bf6e4d358c6f351d0e444b8e1899db2`
- **Tests**: 69 passing (7 test files)
- **Remaining**: Deploy high-rollers-elixir to Fly.io, monitor QuickNode dashboard

---

## Problem

Two background processes iterate over all NFTs making **individual RPC calls per token**, burning through QuickNode's Arbitrum RPC allowance:

### OwnershipReconciler — PRIMARY OFFENDER (Arbitrum/QuickNode)
- **Schedule**: Every 5 minutes
- **File**: `lib/high_rollers/ownership_reconciler.ex`
- **Line 196**: `NFTContract.get_owner_of(token_id)` → 1 `eth_call` per NFT to Arbitrum
- **Line 232**: `NFTRewarder.get_nft_owner(token_id)` → 1 `eth_call` per NFT to Rogue Chain (only when owner changed)
- **Impact**: **2,414 Arbitrum RPC calls every 5 min = ~29,000/hour**
- With retry logic (3 retries), worst case: 7,242 calls per cycle

### EarningsSyncer `sync_time_reward_claim_times` — SECONDARY (Rogue Chain)
- **Schedule**: Every 60 seconds
- **File**: `lib/high_rollers/earnings_syncer.ex`
- **Line 245**: `NFTRewarder.get_time_reward_raw(token_id)` → 1 `eth_call` per special NFT
- Special NFTs = token IDs 2340-2700 = ~361 NFTs
- **Impact**: ~361 Rogue RPC calls/min = ~21,600/hour

### What's already efficient (no changes needed)
- Event pollers (`ArbitrumEventPoller`, `RogueRewardPoller`) use `eth_getLogs` with block ranges
- `get_batch_nft_earnings` already uses a single contract call for 100 NFTs at a time
- The per-NFT `ownerOf` loop and `timeRewardInfo` loop are the only problems

---

## Solution: Two-Pronged Approach

### Arbitrum: Multicall3
- Pre-deployed at `0xcA11bde05977b3631167028862bE2a173976CA11` on Arbitrum (verified)
- Wraps N `ownerOf` calls inside a single `eth_call` — QuickNode bills as **1 call**
- **NOT deployed on Rogue Chain** — so we use a different approach there

### Rogue Chain: NFTRewarder Contract Upgrade
- Add batch view functions to NFTRewarder (UUPS proxy, already upgradeable)
- Follows the exact pattern of existing `getBatchNFTEarnings` which already works
- Two new view functions:
  - `getBatchTimeRewardRaw(uint256[])` — for EarningsSyncer
  - `getBatchNFTOwners(uint256[])` — for OwnershipReconciler rewarder checks
- No new contract deployment needed, just upgrade existing proxy
- Zero risk to existing state (read-only view functions only)

### Impact Summary

| Process | Current calls/cycle | After batching (50/batch) | Reduction |
|---------|--------------------:|---------------------------:|----------:|
| OwnershipReconciler (Arbitrum) | 2,414 | 49 | **98%** |
| EarningsSyncer time rewards (Rogue) | ~361 | 8 | **98%** |
| **Hourly total (Arbitrum/QuickNode)** | **~29,000** | **~588** | **98%** |

---

## Implementation

### Phase 0: Upgrade NFTRewarder on Rogue Chain

Upgrade NFTRewarder to add two batch view functions. The contract is a UUPS proxy at `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` on Rogue Chain.

**Contract source**: `contracts/bux-booster-game/contracts/NFTRewarder.sol` (1,498 lines, flattened)

#### New function 1: `getBatchTimeRewardRaw`

Add after the existing `getBatchNFTEarnings` function (~line 1202). Follows same pattern.

```solidity
/**
 * @notice Batch query time reward info for multiple NFTs.
 * @param tokenIds Array of token IDs to query.
 * @return startTimes Array of start timestamps (0 if not registered for time rewards)
 * @return lastClaimTimes Array of last claim timestamps
 * @return totalClaimeds Array of total claimed amounts (wei)
 */
function getBatchTimeRewardRaw(uint256[] calldata tokenIds) external view returns (
    uint256[] memory startTimes,
    uint256[] memory lastClaimTimes,
    uint256[] memory totalClaimeds
) {
    uint256 len = tokenIds.length;
    startTimes = new uint256[](len);
    lastClaimTimes = new uint256[](len);
    totalClaimeds = new uint256[](len);

    for (uint256 i = 0; i < len; i++) {
        TimeRewardInfo storage info = timeRewardInfo[tokenIds[i]];
        startTimes[i] = info.startTime;
        lastClaimTimes[i] = info.lastClaimTime;
        totalClaimeds[i] = info.totalClaimed;
    }
}
```

#### New function 2: `getBatchNFTOwners`

```solidity
/**
 * @notice Batch query NFT owners from the nftMetadata mapping.
 * @param tokenIds Array of token IDs to query.
 * @return owners Array of owner addresses (address(0) if not registered)
 */
function getBatchNFTOwners(uint256[] calldata tokenIds) external view returns (
    address[] memory owners
) {
    uint256 len = tokenIds.length;
    owners = new address[](len);

    for (uint256 i = 0; i < len; i++) {
        owners[i] = nftMetadata[tokenIds[i]].owner;
    }
}
```

#### Upgrade process:
1. Add both functions to `NFTRewarder.sol`
2. Compile with Hardhat (same settings as previous upgrades)
3. Deploy new implementation
4. Call `upgradeToAndCall` on the proxy
5. Verify on RogueScan
6. **Do NOT run the deploy yourself** — prepare the script and tell the user the command

---

### Phase 1: Multicall3 Helper Module (Arbitrum Only)

**Create**: `lib/high_rollers/contracts/multicall3.ex`

This module provides a Multicall3 interface for Arbitrum batching only.

```elixir
defmodule HighRollers.Contracts.Multicall3 do
  @moduledoc """
  Multicall3 helper for batching multiple eth_call requests into one.

  Used for Arbitrum only. Multicall3 is at canonical address:
  0xcA11bde05977b3631167028862bE2a173976CA11

  For Rogue Chain batching, use native batch functions on NFTRewarder instead.
  """

  @multicall3_address "0xcA11bde05977b3631167028862bE2a173976CA11"
  @default_batch_size 50

  @doc """
  Execute multiple calls via Multicall3.aggregate3().

  Takes a list of {target_address, calldata} tuples.
  All calls use allowFailure=true so one failure doesn't revert the batch.

  Returns {:ok, [{success, return_data}, ...]} or {:error, reason}.
  """
  def aggregate3(rpc_url, calls, opts \\ [])

  @doc """
  Execute calls in batches, returning all results in order.

  Splits `calls` into chunks of `batch_size` (default 50),
  executes each chunk as a single Multicall3 call, then
  concatenates results.

  Options:
    - batch_size: number of calls per Multicall3 invocation (default: 50)
    - batch_delay_ms: delay between batches for rate limiting (default: 200)
    - timeout: RPC timeout in ms (default: 30_000)
    - max_retries: max retry attempts (default: 3)
  """
  def aggregate3_batched(rpc_url, calls, opts \\ [])
end
```

#### Key implementation details

1. **ABI encoding for `aggregate3`**:
   - Function selector: `keccak256("aggregate3((address,bool,bytes)[])")` → first 4 bytes
   - Each `Call3` struct is encoded as: `address (padded to 32 bytes) + bool (32 bytes) + bytes offset/length/data`
   - The outer array is a dynamic type with offset, length, then elements

2. **ABI decoding for `Result[]`**:
   - Each `Result` = `{bool success, bytes returnData}`
   - Dynamic array of dynamic structs

3. **Error handling**:
   - `allowFailure=true` on all calls so one bad token ID doesn't fail the batch
   - Return `{false, error_data}` for failed sub-calls, let caller handle

4. **Rate limiting**:
   - `aggregate3_batched` includes configurable delay between batches (default 200ms)

---

### Phase 2: Batch `ownerOf` in OwnershipReconciler (Arbitrum via Multicall3)

**Modify**: `lib/high_rollers/ownership_reconciler.ex`

#### Current flow (lines 172-192):
```elixir
defp reconcile_batch(nfts) do
  Enum.reduce(nfts, {0, 0, 0}, fn nft, {m_acc, r_acc, e_acc} ->
    case reconcile_single_nft(nft) do  # ← 1 RPC call per NFT
      ...
    end
  end)
end

defp reconcile_single_nft(nft) do
  case HighRollers.Contracts.NFTContract.get_owner_of(nft.token_id) do  # ← eth_call
    ...
  end
end
```

#### New flow:
```elixir
defp reconcile_batch(nfts) do
  token_ids = Enum.map(nfts, & &1.token_id)

  case NFTContract.get_batch_owners(token_ids) do  # ← 1 Multicall3 call for all 50
    {:ok, owner_results} ->
      Enum.zip(nfts, owner_results)
      |> Enum.reduce({0, 0, 0}, fn {nft, owner_result}, acc ->
        reconcile_nft_with_owner(nft, owner_result, acc)
      end)

    {:error, reason} ->
      Logger.warning("[OwnershipReconciler] Batch owner query failed: #{inspect(reason)}")
      {0, 0, length(nfts)}  # Count all as errors
  end
end
```

#### Also add to `lib/high_rollers/contracts/nft_contract.ex`:
```elixir
@doc """
Batch query ownerOf for multiple token IDs via Multicall3.
Returns {:ok, [{:ok, owner_address} | {:error, reason}, ...]}
"""
def get_batch_owners(token_ids) when is_list(token_ids) do
  calls = Enum.map(token_ids, fn token_id ->
    data = "0x6352211e" <> encode_uint256(token_id)  # ownerOf selector
    {@contract_address, data}
  end)

  rpc_url = Application.get_env(:high_rollers, :arbitrum_rpc_url)

  case HighRollers.Contracts.Multicall3.aggregate3(rpc_url, calls) do
    {:ok, results} ->
      owners = Enum.map(results, fn
        {true, return_data} -> {:ok, decode_address("0x" <> Base.encode16(return_data, case: :lower))}
        {false, _} -> {:error, :call_failed}
      end)
      {:ok, owners}

    {:error, reason} ->
      {:error, reason}
  end
end
```

---

### Phase 3: Batch `timeRewardInfo` in EarningsSyncer (Rogue via NFTRewarder)

**Modify**: `lib/high_rollers/earnings_syncer.ex`

This phase uses the new `getBatchTimeRewardRaw` function added to NFTRewarder in Phase 0 — a direct contract call, NOT Multicall3.

#### Current flow (lines 214-234):
```elixir
defp sync_time_reward_claim_times do
  special_nfts = HighRollers.NFTStore.get_special_nfts_by_owner(nil)

  special_nfts
  |> Enum.chunk_every(50)
  |> Enum.each(fn batch ->
    Enum.each(batch, fn nft ->
      sync_single_time_reward(nft)  # ← 1 RPC call per NFT
    end)
    Process.sleep(100)
  end)
end
```

#### New flow:
```elixir
defp sync_time_reward_claim_times do
  special_nfts = HighRollers.NFTStore.get_special_nfts_by_owner(nil)

  if Enum.empty?(special_nfts) do
    :ok
  else
    Logger.info("[EarningsSyncer] Syncing time reward claim times for #{length(special_nfts)} special NFTs")

    special_nfts
    |> Enum.chunk_every(50)
    |> Enum.each(fn batch ->
      sync_time_reward_batch(batch)  # ← 1 contract call per 50 NFTs
      Process.sleep(100)
    end)
  end
end

defp sync_time_reward_batch(batch) do
  token_ids = Enum.map(batch, & &1.token_id)

  case NFTRewarder.get_batch_time_reward_raw(token_ids) do
    {:ok, results} ->
      Enum.zip(batch, results)
      |> Enum.each(fn {nft, raw_info} ->
        apply_time_reward_updates(nft, raw_info)
      end)

    {:error, reason} ->
      Logger.warning("[EarningsSyncer] Batch time reward query failed: #{inspect(reason)}")
  end
end
```

#### Also add to `lib/high_rollers/contracts/nft_rewarder.ex`:
```elixir
@doc """
Batch query time reward info via NFTRewarder.getBatchTimeRewardRaw().
Returns {:ok, [%{start_time, last_claim_time, total_claimed}, ...]}

Uses the native batch function on the contract (not Multicall3).
Follows same pattern as get_batch_nft_earnings.
"""
def get_batch_time_reward_raw(token_ids) when is_list(token_ids) do
  selector = function_selector("getBatchTimeRewardRaw(uint256[])")
  array_data = encode_uint256_array(token_ids)
  data = selector <> array_data

  case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
    {:ok, result} ->
      decoded = decode_triple_array(result)

      results =
        token_ids
        |> Enum.with_index()
        |> Enum.map(fn {_token_id, i} ->
          %{
            start_time: Enum.at(decoded.first, i, 0),
            last_claim_time: Enum.at(decoded.second, i, 0),
            total_claimed: Enum.at(decoded.third, i, 0)
          }
        end)

      {:ok, results}

    {:error, reason} ->
      {:error, reason}
  end
end
```

Note: `decode_triple_array` already exists in `nft_rewarder.ex` (used by `get_batch_nft_earnings`). The return format is the same — three parallel uint256 arrays. Rename the internal fields generically or add a second decoder. The existing one uses `.total_earned`, `.pending_amounts`, `.hostess_indices` — adapt or add a generic version.

---

### Phase 4: Batch `nftMetadata` for Rewarder Owner Check (Rogue via NFTRewarder)

**File**: `lib/high_rollers/ownership_reconciler.ex` line 230-252

The `maybe_update_rewarder/2` function calls `NFTRewarder.get_nft_owner(token_id)` for each NFT where ownership changed. Uses the new `getBatchNFTOwners` function added in Phase 0.

#### Add to `lib/high_rollers/contracts/nft_rewarder.ex`:
```elixir
@doc """
Batch query NFT owners from nftMetadata mapping via NFTRewarder.getBatchNFTOwners().
Returns {:ok, [owner_address, ...]}

Uses the native batch function on the contract (not Multicall3).
"""
def get_batch_nft_owners(token_ids) when is_list(token_ids) do
  selector = function_selector("getBatchNFTOwners(uint256[])")
  array_data = encode_uint256_array(token_ids)
  data = selector <> array_data

  case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
    {:ok, result} ->
      owners = decode_address_array(result)
      {:ok, owners}

    {:error, reason} ->
      {:error, reason}
  end
end
```

Note: `decode_address_array` already exists in `nft_rewarder.ex` (line 445-460).

#### Refactor `ownership_reconciler.ex`:
After the batch `ownerOf` query (Phase 2) identifies mismatched NFTs, collect all mismatched token IDs and batch their rewarder owner queries in one call instead of one-by-one.

---

## Implementation Checklist

### Phase 0: NFTRewarder Contract Upgrade
- [x] Add `getBatchTimeRewardRaw(uint256[])` to `contracts/bux-booster-game/contracts/NFTRewarder.sol`
  - [x] Returns three parallel arrays: `startTimes[]`, `lastClaimTimes[]`, `totalClaimeds[]`
  - [x] Reads from `timeRewardInfo` mapping (same as existing `timeRewardInfo(uint256)`)
  - [x] Follows same pattern as `getBatchNFTEarnings`
- [x] Add `getBatchNFTOwners(uint256[])` to `NFTRewarder.sol`
  - [x] Returns single array: `owners[]`
  - [x] Reads from `nftMetadata` mapping (same as existing `nftMetadata(uint256)`)
- [x] Compile with Hardhat (same settings as previous upgrades)
- [x] **Prepare** deploy script and upgrade command — do NOT execute, give to user
- [x] After user deploys: verify on RogueScan

### Phase 1: Multicall3 Module (Arbitrum Only)
- [x] Create `lib/high_rollers/contracts/multicall3.ex`
  - [x] Hardcode `@multicall3_address` to canonical Arbitrum address
  - [x] Implement `aggregate3/3` — single-batch execution
    - [x] ABI-encode `Call3[]` struct array (address, bool, bytes per call)
    - [x] ABI-encode outer dynamic array (offset + length + elements)
    - [x] Make single `eth_call` to Multicall3 address
    - [x] ABI-decode `Result[]` response (bool success + bytes returnData per result)
    - [x] Return `{:ok, [{success, return_data}, ...]}` or `{:error, reason}`
  - [x] Implement `aggregate3_batched/3` — multi-batch with chunking
    - [x] Split calls into chunks of `batch_size` (default 50)
    - [x] Call `aggregate3` for each chunk
    - [x] Concatenate results in order
    - [x] Add configurable delay between batches (default 200ms)
  - [x] Helper: `encode_call3_array/1` — encode list of `{address, calldata}` tuples
  - [x] Helper: `decode_result_array/1` — decode Multicall3 Result[] response
  - [x] Use `HighRollers.RPC.call/4` for the actual HTTP call (inherits retry logic)

### Phase 2: Batch ownerOf (Arbitrum via Multicall3)
- [x] Add `get_batch_owners/1` to `lib/high_rollers/contracts/nft_contract.ex`
  - [x] Build `ownerOf(uint256)` calldata for each token ID
  - [x] Call `Multicall3.aggregate3/3` with Arbitrum RPC URL
  - [x] Decode each result's return data as an address
  - [x] Return `{:ok, [{:ok, address} | {:error, reason}, ...]}` preserving order
- [x] Refactor `reconcile_batch/1` in `ownership_reconciler.ex`
  - [x] Replace per-NFT `reconcile_single_nft` loop with batch query
  - [x] Extract `reconcile_nft_with_owner/3` from existing `reconcile_single_nft/1` logic
  - [x] Handle individual call failures gracefully (skip failed, count as error)
  - [x] Keep the existing `maybe_update_rewarder` logic per-NFT for now (Phase 4)
- [x] Keep `reconcile_single_nft/1` as fallback (don't delete — useful for single-NFT reconcile)

### Phase 3: Batch timeRewardInfo (Rogue via NFTRewarder)
- [x] Add `get_batch_time_reward_raw/1` to `lib/high_rollers/contracts/nft_rewarder.ex`
  - [x] Build `getBatchTimeRewardRaw(uint256[])` calldata
  - [x] Make single `eth_call` to NFTRewarder contract on Rogue Chain
  - [x] Decode response as three parallel uint256 arrays (reuse/adapt `decode_triple_array`)
  - [x] Return `{:ok, [%{start_time, last_claim_time, total_claimed}, ...]}` preserving order
- [x] Refactor `sync_time_reward_claim_times/0` in `earnings_syncer.ex`
  - [x] Replace per-NFT `sync_single_time_reward` loop with batch query
  - [x] Extract `apply_time_reward_updates/2` from existing `sync_single_time_reward/1`
  - [x] Handle failures gracefully (log warning, skip)

### Phase 4: Batch nftMetadata (Rogue via NFTRewarder)
- [x] Add `get_batch_nft_owners/1` to `lib/high_rollers/contracts/nft_rewarder.ex`
  - [x] Build `getBatchNFTOwners(uint256[])` calldata
  - [x] Decode response as address array (reuse existing `decode_address_array`)
  - [x] Return `{:ok, [owner_address, ...]}` preserving order
- [x] Refactor `maybe_update_rewarder` in `ownership_reconciler.ex`
  - [x] Collect all mismatched token IDs from Phase 2 results
  - [x] Batch query nftMetadata for all mismatches at once
  - [x] Process results and enqueue `AdminTxQueue` updates

### Final
- [x] Verify no regressions — existing single-call functions remain for other callers
- [x] Add logging: log batch sizes and RPC call counts for monitoring
- [x] Test on dev with both nodes running (GlobalSingleton behavior)
- [x] Monitor QuickNode dashboard after deploy to confirm reduction

---

## Testing Plan

### Test File: `test/high_rollers/contracts/multicall3_test.exs`

Test the Multicall3 module in isolation using mocked RPC responses.

```
describe "aggregate3/3" do
  - test "encodes single call correctly"
    Build one {address, calldata} tuple, verify the encoded payload matches
    expected ABI encoding for aggregate3((address,bool,bytes)[])

  - test "encodes multiple calls correctly"
    Build 3 calls with different addresses and calldata, verify encoding

  - test "decodes successful results"
    Mock RPC returning Result[] with all success=true, verify decoded tuples

  - test "decodes mixed success/failure results"
    Mock RPC returning some success=true, some success=false, verify each

  - test "handles empty call list"
    Pass empty list, should return {:ok, []}

  - test "handles RPC error"
    Mock RPC returning {:error, reason}, verify error propagated

  - test "handles malformed response"
    Mock RPC returning unexpected data, verify graceful error
end

describe "aggregate3_batched/3" do
  - test "single batch (under batch_size)"
    Pass 30 calls with batch_size=50, verify single RPC call made

  - test "multiple batches"
    Pass 120 calls with batch_size=50, verify 3 RPC calls made (50+50+20)

  - test "results maintain order across batches"
    Pass 120 calls, verify results[0..49] from batch 1, results[50..99]
    from batch 2, results[100..119] from batch 3

  - test "batch delay is respected"
    Pass 100 calls with batch_size=50, measure elapsed time >= batch_delay_ms

  - test "partial batch failure"
    Mock first batch succeeding, second batch RPC error,
    verify error returned (or partial results depending on design choice)

  - test "custom batch_size option"
    Pass batch_size: 25, verify 4 batches for 100 calls
end
```

### Test File: `test/high_rollers/contracts/nft_contract_test.exs`

Add tests for the new `get_batch_owners/1` function.

```
describe "get_batch_owners/1" do
  - test "returns owners for multiple token IDs"
    Mock Multicall3.aggregate3 returning successful owner addresses,
    verify each token_id maps to correct owner

  - test "handles individual call failures"
    Mock one sub-call returning {false, <<>>}, verify that token gets
    {:error, :call_failed} while others get {:ok, address}

  - test "preserves order matching input token_ids"
    Pass [5, 3, 1], verify results[0] is owner of token 5, etc.

  - test "handles empty token_ids list"
    Pass [], verify {:ok, []}

  - test "handles Multicall3 total failure"
    Mock aggregate3 returning {:error, reason}, verify error propagated

  - test "correctly encodes ownerOf calldata"
    Verify the calldata starts with 0x6352211e (ownerOf selector)
    followed by the token ID as uint256

  - test "correctly decodes address from return data"
    Pass raw 32-byte padded address, verify decoded to 0x-prefixed
    lowercase 40-char hex string
end
```

### Test File: `test/high_rollers/contracts/nft_rewarder_test.exs`

Add tests for new batch functions.

```
describe "get_batch_time_reward_raw/1" do
  - test "returns time reward info for multiple token IDs"
    Mock RPC returning triple-array response,
    verify decoded start_time, last_claim_time, total_claimed for each

  - test "preserves order matching input token_ids"
    Pass [2340, 2350, 2360], verify results match input order

  - test "handles empty token_ids list"
    Pass [], verify {:ok, []}

  - test "handles RPC error"
    Mock RPC returning {:error, reason}, verify error propagated

  - test "correctly encodes getBatchTimeRewardRaw calldata"
    Verify calldata starts with correct function selector
    followed by encoded uint256 array

  - test "decodes zero values correctly"
    Return all-zero arrays, verify start_time=0, last_claim_time=0,
    total_claimed=0 (unregistered NFT)

  - test "decodes large wei values correctly"
    Return arrays with large total_claimed (e.g. 1e18),
    verify integer is correct
end

describe "get_batch_nft_owners/1" do
  - test "returns owners for multiple token IDs"
    Mock RPC returning address array, verify decoded owners

  - test "returns zero address for unregistered NFTs"
    Mock response with 0x000...000 address, verify returned as zero address

  - test "preserves order matching input token_ids"

  - test "handles empty token_ids list"

  - test "handles RPC error"
end
```

### Test File: `test/high_rollers/ownership_reconciler_test.exs`

Add/modify tests for the refactored batch reconciliation.

```
describe "reconcile_batch/1 (batched)" do
  - test "updates Mnesia when contract owner differs"
    Mock batch owners returning different owner for one NFT,
    verify NFTStore.update_owner called with new owner

  - test "no updates when all owners match"
    Mock batch owners matching Mnesia, verify no updates

  - test "handles batch query failure gracefully"
    Mock get_batch_owners returning {:error, _}, verify errors counted

  - test "handles individual failures in batch"
    Mock one token returning {:error, :call_failed} in results,
    verify it's counted as error, others processed normally

  - test "queues NFTRewarder update when rewarder owner differs"
    Mock Arbitrum owner changed AND rewarder owner stale,
    verify AdminTxQueue.enqueue_update_ownership called

  - test "case-insensitive owner comparison"
    Mock owner "0xAbCd..." vs Mnesia "0xabcd...", verify no update

  - test "processes all NFTs across multiple batches"
    Create 120 test NFTs, verify all processed (2 batches of 50 + 1 of 20)
end
```

### Test File: `test/high_rollers/earnings_syncer_test.exs`

Add/modify tests for the refactored time reward sync.

```
describe "sync_time_reward_claim_times/0 (batched)" do
  - test "syncs start_time from contract when different"
    Mock batch time reward returning different start_time,
    verify NFTStore.update_time_reward called

  - test "syncs last_claim_time from contract when different"
    Mock batch time reward returning different last_claim_time,
    verify update applied

  - test "syncs total_claimed from contract when different"
    Mock contract returning larger total_claimed,
    verify update with stringified wei value

  - test "no updates when all values match"
    Mock matching values, verify no NFTStore updates

  - test "skips NFTs with zero start_time"
    Mock start_time=0 (unregistered), verify no update applied

  - test "handles batch query failure"
    Mock get_batch_time_reward_raw returning {:error, _},
    verify warning logged, no crash

  - test "handles individual failures in batch"
    Mock one token {:error, :call_failed}, verify others still processed

  - test "only queries special NFTs (2340-2700)"
    Verify get_special_nfts_by_owner(nil) is called, not get_all()
end
```

### Test File: `test/high_rollers/contracts/multicall3_encoding_test.exs`

Dedicated test file for ABI encoding/decoding correctness.

```
describe "ABI encoding" do
  - test "aggregate3 selector is correct"
    Verify keccak256("aggregate3((address,bool,bytes)[])") first 4 bytes
    matches expected selector: 0x82ad56cb

  - test "single Call3 struct encoding"
    Encode one call, manually compute expected ABI bytes, compare

  - test "Call3 with varying calldata lengths"
    Encode calls with 4-byte, 36-byte, and 68-byte calldata,
    verify padding and offsets are correct

  - test "empty calldata"
    Encode call with empty bytes calldata, verify valid encoding

  - test "address encoding is zero-padded to 32 bytes"
    Verify address is left-padded with 12 zero bytes
end

describe "ABI decoding" do
  - test "single Result decoding"
    Manually construct valid Result[] ABI bytes for 1 result,
    verify decoded {true, return_data}

  - test "multiple Results decoding"
    Construct 3 results with varying return data lengths, verify all decoded

  - test "empty return data on failure"
    Construct {false, <<>>} result, verify decoded correctly

  - test "large return data (multiple slots)"
    Construct result with 128 bytes of return data, verify fully decoded
end
```

### Integration Tests (Optional — requires RPC access)

```
describe "integration (requires RPC)" do
  @tag :integration
  @tag :external

  - test "Multicall3 contract exists on Arbitrum"
    Call eth_getCode for canonical Multicall3 address on Arbitrum, verify non-empty

  - test "batch ownerOf returns real owners"
    Call get_batch_owners([1, 2, 3]) against real Arbitrum,
    verify returns valid addresses

  - test "getBatchTimeRewardRaw works on Rogue Chain"
    Call get_batch_time_reward_raw([2340, 2341]) against real Rogue Chain,
    verify returns valid timestamps

  - test "getBatchNFTOwners works on Rogue Chain"
    Call get_batch_nft_owners([1, 2, 3]) against real Rogue Chain,
    verify returns valid addresses
end
```

### Test Helpers

Create `test/support/multicall3_fixtures.ex` with:
- Pre-computed ABI-encoded payloads for known inputs
- Pre-computed response bytes for known outputs
- Mock RPC response builders
- Helper to build fake NFT structs for Mnesia

### Running Tests

```bash
# Unit tests only (no RPC calls)
mix test test/high_rollers/contracts/multicall3_test.exs
mix test test/high_rollers/contracts/multicall3_encoding_test.exs
mix test test/high_rollers/contracts/nft_contract_test.exs
mix test test/high_rollers/contracts/nft_rewarder_test.exs
mix test test/high_rollers/ownership_reconciler_test.exs
mix test test/high_rollers/earnings_syncer_test.exs

# All multicall-related tests
mix test --only multicall

# Integration tests (requires RPC access)
mix test --only integration

# Everything
mix test
```

---

## ABI Reference

### Multicall3.aggregate3 Encoding (Arbitrum)

**Function signature**: `aggregate3((address,bool,bytes)[])`
**Selector**: `0x82ad56cb`

**Encoding layout for N calls**:

```
[4 bytes]  function selector (0x82ad56cb)
[32 bytes] offset to Call3[] array data (0x20 = 32)
[32 bytes] array length (N)
[32 bytes × N] offsets to each Call3 struct (relative to array start)
[variable] Call3 struct data for each call:
  [32 bytes] target address (left-padded)
  [32 bytes] allowFailure (bool, 0 or 1)
  [32 bytes] offset to bytes callData
  [32 bytes] callData length
  [variable] callData (padded to 32-byte boundary)
```

### Multicall3 Result[] Decoding

**Return layout**:
```
[32 bytes] offset to Result[] array data
[32 bytes] array length (N)
[32 bytes × N] offsets to each Result struct
[variable] Result struct data for each:
  [32 bytes] success (bool)
  [32 bytes] offset to bytes returnData
  [32 bytes] returnData length
  [variable] returnData (padded to 32-byte boundary)
```

### NFTRewarder.getBatchTimeRewardRaw Encoding (Rogue Chain)

**Function signature**: `getBatchTimeRewardRaw(uint256[])`
**Return**: Three parallel uint256 arrays (same format as `getBatchNFTEarnings`)

### NFTRewarder.getBatchNFTOwners Encoding (Rogue Chain)

**Function signature**: `getBatchNFTOwners(uint256[])`
**Return**: Single address array

### ownerOf Return Data (Arbitrum)
```
[32 bytes] address (left-padded with 12 zero bytes)
```

---

## Rollback Plan

If batching causes issues:

1. The old per-NFT functions (`get_owner_of`, `get_time_reward_raw`, `get_nft_owner`) remain untouched
2. Revert `ownership_reconciler.ex` and `earnings_syncer.ex` to use per-NFT loops
3. The Multicall3 module can stay — it's additive and unused code causes no harm
4. The NFTRewarder contract upgrade is safe — only adds view functions, no state changes

---

## Files Summary

| Action | File | Description |
|--------|------|-------------|
| **Upgrade** | `contracts/bux-booster-game/contracts/NFTRewarder.sol` | Add `getBatchTimeRewardRaw` + `getBatchNFTOwners` |
| **Create** | `lib/high_rollers/contracts/multicall3.ex` | Multicall3 helper (Arbitrum only) |
| **Modify** | `lib/high_rollers/contracts/nft_contract.ex` | Add `get_batch_owners/1` |
| **Modify** | `lib/high_rollers/contracts/nft_rewarder.ex` | Add `get_batch_time_reward_raw/1` + `get_batch_nft_owners/1` |
| **Modify** | `lib/high_rollers/ownership_reconciler.ex` | Use batch owners |
| **Modify** | `lib/high_rollers/earnings_syncer.ex` | Use batch time rewards |
| **Create** | `test/high_rollers/contracts/multicall3_test.exs` | Multicall3 unit tests |
| **Create** | `test/high_rollers/contracts/multicall3_encoding_test.exs` | ABI encoding tests |
| **Create/Modify** | `test/high_rollers/contracts/nft_contract_test.exs` | Batch owner tests |
| **Create/Modify** | `test/high_rollers/contracts/nft_rewarder_test.exs` | Batch time reward + owner tests |
| **Create/Modify** | `test/high_rollers/ownership_reconciler_test.exs` | Reconciler batch tests |
| **Create/Modify** | `test/high_rollers/earnings_syncer_test.exs` | Syncer batch tests |
| **Create** | `test/support/multicall3_fixtures.ex` | Test helpers and fixtures |
