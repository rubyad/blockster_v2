# Airdrop Runbook — Operating Guide

Step-by-step instructions to fund, activate, run, and settle an airdrop round.

## Prerequisites

- [ ] AirdropVault V3 deployed on Rogue Chain: `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c`
- [ ] AirdropPrizePool deployed on Arbitrum One: `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1`
- [ ] BUX Minter deployed to `bux-minter.fly.dev` with `VAULT_ADMIN_PRIVATE_KEY` secret set
- [ ] Vault Admin wallet (`0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`) has ETH on both Rogue and Arbitrum for gas
- [ ] USDT funded into PrizePool contract (at least $5 for current test pool)
- [ ] `VAULT_ADMIN_PRIVATE_KEY` in `contracts/bux-booster-game/.env` (for hardhat scripts)

---

## Contract Addresses

| Contract | Chain | Address |
|----------|-------|---------|
| AirdropVault V3 (Proxy) | Rogue Chain (560013) | `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c` |
| AirdropPrizePool (Proxy) | Arbitrum One (42161) | `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1` |
| BUX Token | Rogue Chain | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` |
| USDT | Arbitrum One | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| Vault Admin | Both | `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` |

---

## Architecture Overview

The airdrop has two parallel tracks:

1. **On-chain (Rogue Chain)**: User's smart wallet does `BUX.approve()` + `vault.deposit()` entirely client-side via `AirdropDepositHook`. AirdropVault V3 has a public `deposit(externalWallet, amount)` function.

2. **Backend (Elixir)**: After the on-chain deposit confirms, LiveView records the entry in Postgres and deducts BUX from Mnesia. The Settler GenServer automatically closes rounds and draws winners when the timer expires.

3. **On-chain sync (Rogue Chain)**: After off-chain draw, Settler calls `drawWinners(serverSeed)` to reveal the seed on-chain, then pushes each winner via `setWinner()` so `getWinnerInfo()` works on RogueScan.

4. **Prize payouts (Arbitrum)**: Prizes are registered on AirdropPrizePool via BUX Minter. Winners claim USDT on Arbitrum.

### Deposit Flow (Current)

```
User clicks "Redeem X BUX"
  → LiveView validates (phone verified, wallet connected, balance, round open)
  → pushes "airdrop_deposit" event to AirdropDepositHook (JS)
    → JS: check allowance (localStorage cache + on-chain)
    → JS: if needed, BUX.approve(vault, MAX_UINT256)
    → JS: vault.deposit(externalWallet, amountWei)
    → JS: wait for receipt, parse BuxDeposited event
    → JS: push "airdrop_deposit_complete" back to LiveView
  → LiveView: Airdrop.redeem_bux() records entry in Postgres, deducts Mnesia
  → LiveView: sync on-chain balances async
  → PubSub broadcasts updated stats to all users
```

### Settlement Flow (Automatic)

```
Settler GenServer schedules timer for round.end_time
  → Timer fires
  → Try on-chain close (BuxMinter.airdrop_close) → fallback to RPC block hash
  → Airdrop.close_round() in Postgres
  → Airdrop.draw_winners() — provably fair keccak256 algorithm
  → Sync draw on-chain: BuxMinter.airdrop_draw_winners(server_seed)
  → PubSub broadcast :airdrop_drawn → all LiveView clients update instantly
  → For each winner (in background Task):
    → Register prize on Arbitrum PrizePool (BuxMinter.airdrop_set_prize)
    → Push winner to vault on Rogue (BuxMinter.airdrop_set_winner)
    → PubSub broadcast :airdrop_winner_revealed → UI reveals one by one
```

---

## Phase 1: Fund the Prize Pool

Fund the AirdropPrizePool on Arbitrum with USDT before opening the round.

### Option A: Script (recommended)

Edit `AMOUNT_USD` in the script if needed, then:

```bash
cd contracts/bux-booster-game
npx hardhat run scripts/fund-airdrop-prize-pool.js --network arbitrumOne
```

This approves + calls `fundPrizePool()`. Verify pool balance in output.

### Option B: Manual

1. Send USDT to Vault Admin wallet on Arbitrum
2. From Vault Admin, approve PrizePool to spend USDT
3. Call `fundPrizePool(amount)` on PrizePool

### Verify

```bash
# Check pool balance (via script output or Arbiscan read contract)
# PrizePool → getPoolBalance() should show funded amount
```

---

## Phase 2: Start a Round

`Airdrop.create_round/1` uses the **AirdropVault as the source of truth** for round IDs:

1. Generates server seed + SHA256 commitment hash
2. Calls `BuxMinter.airdrop_start_round(commitmentHash, endTime)` → on-chain `startRound()`
3. Extracts the vault's `roundId` from the response — this becomes the DB `round_id`
4. Creates round in Postgres with status "open"
5. Syncs the AirdropPrizePool (Arbitrum) to the same roundId in the background
6. Notifies the Settler GenServer to schedule auto-settlement at `end_time`

**The vault must succeed** — if `startRound()` fails, no DB row is created and an error is returned.

```elixir
# On the Elixir server (IEx or remote console)
alias BlocksterV2.Airdrop

# Choose end time (e.g., 7 days from now)
end_time = DateTime.add(DateTime.utc_now(), 7 * 86400, :second)
{:ok, round} = Airdrop.create_round(end_time)

round.round_id          # matches vault's roundId (e.g., 4)
round.commitment_hash   # SHA256 of server_seed (public)
round.server_seed       # SECRET — do NOT share until after draw
round.start_round_tx    # on-chain tx hash
```

> **Note**: The vault call is required. If it fails, you'll get `{:error, {:vault_start_failed, reason}}`. Check that the BUX Minter is running and `VAULT_ADMIN_PRIVATE_KEY` is set.

---

## Phase 3: Users Deposit BUX (Automatic)

Once the round is open, users go to `/airdrop` and deposit BUX. This is fully automatic — no operator action needed.

1. User enters amount → clicks "Redeem X BUX"
2. LiveView pushes to `AirdropDepositHook` (client-side JS)
3. JS hook: checks BUX allowance → approves if needed → calls `vault.deposit()`
4. On-chain deposit confirmed → JS pushes `airdrop_deposit_complete` back to LiveView
5. LiveView records entry in Postgres (position block) and deducts Mnesia balance
6. PubSub broadcasts updated stats to all connected users
7. Receipt panel shows position block (#start–#end) and deposit tx hash

### What happens per deposit:

- **On-chain**: `BUX.approve()` (once, cached) + `vault.deposit(externalWallet, amount)` from user's smart wallet
- **Postgres**: Entry record with `start_position`, `end_position`, `amount`, `deposit_tx`
- **Mnesia**: BUX balance deducted (via EngagementTracker)
- **On-chain sync**: `BuxMinter.sync_user_balances_async` refreshes Mnesia from on-chain

### Monitor

```elixir
# Check round stats
Airdrop.get_total_entries(round_id)
Airdrop.get_participant_count(round_id)
```

---

## Phase 4: Close the Round (Automatic via Settler)

The Settler GenServer automatically closes the round when `end_time` is reached. No manual action needed.

### What the Settler does:

1. Tries `BuxMinter.airdrop_close(round_id)` → on-chain `closeAirdrop()` captures block hash
2. If on-chain close fails, falls back to fetching latest Rogue Chain block hash via RPC
3. Calls `Airdrop.close_round(round_id, block_hash)` → status changes to "closed"
4. Immediately proceeds to draw winners (Phase 5)

### Manual close (if Settler is down):

```elixir
alias BlocksterV2.Airdrop

# Get block hash from Rogue Chain
block_hash = "0x..."  # Get from RogueScan or RPC call

{:ok, closed} = Airdrop.close_round(round_id, block_hash)
closed.status  # => "closed"
```

---

## Phase 5: Draw Winners (Automatic via Settler)

The Settler draws winners immediately after closing. No manual action needed.

### What happens:

1. Combines `server_seed + block_hash` → `keccak256` → combined seed
2. For each winner i (0–32): `keccak256(combined, i) % total_entries + 1` → winning position
3. Maps position to the entry that contains it → winner's wallet
4. Creates 33 Winner records with prize amounts
5. Broadcasts `:airdrop_drawn` via PubSub → all connected users see results instantly

### Manual draw (if needed):

```elixir
alias BlocksterV2.Airdrop

{:ok, drawn} = Airdrop.draw_winners(round_id)
drawn.status  # => "drawn"

winners = Airdrop.get_winners(round_id)
length(winners)  # => 33

Airdrop.verify_fairness(round_id)  # => true
```

---

## Phase 6: Register Prizes & Winners (Automatic via Settler)

The Settler automatically registers all 33 prizes on both chains after drawing winners.

### What happens (for each winner):

1. **PrizePool (Arbitrum)**: `BuxMinter.airdrop_set_prize(round_id, winner_index, wallet, prize_usdt)` → registers USDT prize for claiming
2. **Vault (Rogue)**: `BuxMinter.airdrop_set_winner(round_id, prize_position, winner_data)` → pushes winner data so `getWinnerInfo()` works on RogueScan
3. **PubSub**: Broadcasts `:airdrop_winner_revealed` → UI reveals winners one by one

### Manual registration (if Settler's registration failed):

```elixir
alias BlocksterV2.{Airdrop, BuxMinter}

winners = Airdrop.get_winners(round_id)

for w <- winners do
  wallet = w.external_wallet || w.wallet_address

  # Register prize on Arbitrum
  {:ok, _} = BuxMinter.airdrop_set_prize(round_id, w.winner_index, wallet, w.prize_usdt)

  # Push winner to vault on Rogue (prize_position is 1-indexed)
  winner_data = %{
    random_number: w.random_number,
    blockster_wallet: w.wallet_address,
    external_wallet: w.external_wallet || w.wallet_address,
    bux_redeemed: w.deposit_amount,
    block_start: w.deposit_start,
    block_end: w.deposit_end
  }
  {:ok, _} = BuxMinter.airdrop_set_winner(round_id, w.winner_index + 1, winner_data)

  IO.puts("Set prize #{w.winner_index}: $#{w.prize_usd / 100} to #{wallet}")
end
```

### Verify

```
# On Arbiscan, read PrizePool contract:
# getPrize(roundId, 0) → should show 1st place winner + 650_000 (=$0.65)
# getRoundPrizeTotal(roundId) → should show 5_000_000 (=$5.00)
```

---

## Phase 7: Winners Claim Prizes (via UI)

Winners see their results on `/airdrop` and click "Claim" buttons.

### Flow (fully wired):

1. Winner clicks "Claim" on `/airdrop`
2. LiveView calls `BuxMinter.airdrop_claim(round_id, winner_index)` via `start_async`
3. BUX Minter calls `sendPrize(roundId, winnerIndex)` on Arbitrum PrizePool
4. USDT transferred to winner's external wallet on Arbitrum
5. Returns Arbitrum tx hash → stored as `claim_tx` in Postgres
6. Winner record updated with `claimed: true` and real Arbitrum tx hash

### Manual claim (admin-initiated)

```elixir
# If a winner can't claim via UI, admin can trigger it:
{:ok, result} = BuxMinter.airdrop_claim(round_id, winner_index)
# result.txHash → Arbitrum transaction hash

# Then update the winner record:
Airdrop.claim_prize(user_id, round_id, winner_index, result.txHash, external_wallet)
```

---

## Phase 8: Post-Round Cleanup

### PrizePool round sync (automatic)

The PrizePool on Arbitrum is automatically synced to the vault's roundId when `create_round` is called. If manual sync is needed:

```elixir
# Sync PrizePool to a specific roundId
BlocksterV2.BuxMinter.airdrop_sync_prize_pool_round(target_round_id)
```

### Withdraw remaining BUX from vault (optional)

```
# On Rogue Chain, call withdrawBux(roundId) on AirdropVault
# Returns deposited BUX to vault admin
```

### Verify everything

```elixir
round = Airdrop.get_round(round_id)
round.status  # => "drawn"

winners = Airdrop.get_winners(round_id)
claimed = Enum.count(winners, & &1.claimed)
IO.puts("#{claimed}/33 prizes claimed")

# Provably fair
Airdrop.verify_fairness(round_id)
{:ok, data} = Airdrop.get_verification_data(round_id)
# data.server_seed, data.commitment_hash, data.block_hash_at_close
```

---

## Quick Reference — Prize Structure

| Place | Prize (USD) | Prize (USDT raw) | Winner Index |
|-------|-------------|-------------------|--------------|
| 1st | $250 | 250,000,000 | 0 |
| 2nd | $150 | 150,000,000 | 1 |
| 3rd | $100 | 100,000,000 | 2 |
| 4th–33rd | $50 each | 50,000,000 | 3–32 |
| **Total** | **$2,000** | **2,000,000,000** | **33 winners** |

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/blockster_v2/airdrop.ex` | Core context: rounds, entries, winners, provably fair |
| `lib/blockster_v2/airdrop/settler.ex` | Auto-settlement GenServer (close → draw → register prizes) |
| `lib/blockster_v2_web/live/airdrop_live.ex` | LiveView UI + event handlers |
| `assets/js/hooks/airdrop_deposit.js` | Client-side approve + deposit hook (V2) |
| `lib/blockster_v2/bux_minter.ex` | Elixir client for BUX Minter service |
| `bux-minter/index.js` | Node.js minter service (start/close/draw/set-winner/set-prize/claim endpoints) |
| `contracts/bux-booster-game/contracts/AirdropVaultV3.sol` | V3 contract: simplified draw, server pushes winners |
| `contracts/bux-booster-game/scripts/upgrade-airdrop-vault-v3.js` | Deploy script for V3 upgrade |
| `contracts/bux-booster-game/scripts/fund-airdrop-prize-pool.js` | Fund PrizePool with USDT |

---

## Upgrade History

### V1 → V2 (2026-02-28)

V2 adds a public `deposit()` using `msg.sender` (V1's `depositFor()` was `onlyOwner`).

```bash
cd contracts/bux-booster-game
npx hardhat run scripts/upgrade-airdrop-vault-v2.js --network rogueMainnet
```

| Step | Tx Hash | Address |
|------|---------|---------|
| V2 Implementation | — | `0x1262900820b743D6dE7AB3f5fb76A865d074516C` |
| upgradeToAndCall | `0x10f04f0d85045d8d8b00ac061e172a8ee731f3f1a8323af8d59f6ab20dc30fcd` | — |
| initializeV2 | `0xe6966d7cd3ae4af8b72d62d9bb3882c47136125bf5b54c22acea585356ec1702` | — |

### V2 → V3 (2026-02-28)

V3 simplifies the draw: removes on-chain SHA256 verification and winner computation. The server computes winners off-chain (Elixir) and pushes them to the contract via `setWinner()`.

**Why**: V2's `drawWinners()` re-hashed the server seed as raw `bytes32`, but Elixir's commitment hashed the hex string — different inputs, different SHA256 outputs, so the on-chain verify always reverted.

**Changes**:
- `drawWinners(bytes32)` — stores seed + marks drawn, no SHA256 check
- New `setWinner()` — server pushes each winner's data on-chain
- New `WinnerV3` struct + `_winnersV3` mapping (avoids storage collision with V2's `_winners`)
- `getWinnerInfo(position)` / `verifyFairness()` — no round ID needed (uses current round)

```bash
cd contracts/bux-booster-game
npx hardhat run scripts/upgrade-airdrop-vault-v3.js --network rogueMainnet
```

| Step | Tx Hash | Address |
|------|---------|---------|
| V3 Implementation | — | `0x1d540f6bc7d55DCa7F392b9cc7668F2f14d330F9` |
| upgradeToAndCall | `0x337bcd8ede8636890e094513721f5daba690b361a8a6799775fdda9bf681c7a3` | — |
| initializeV3 | included in upgradeToAndCall | — |

Verification: `version()` → "v3", `owner()` → `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`, `roundId()` → 5

---

## Remaining TODOs

1. **Scale prize structure**: Update `@prize_structure` in `airdrop.ex` from test pool ($5) to production amounts

### What's already automated

- **Deposits**: Fully client-side via AirdropDepositHook (approve + deposit on-chain, record in Postgres)
- **Round creation**: `create_round` calls vault `startRound()` → uses vault's roundId as DB round_id → syncs PrizePool in background
- **Round ID sync**: Vault is source of truth. DB follows vault. PrizePool follows vault (auto-synced on round creation)
- **Startup reconciliation**: Settler verifies vault vs DB round IDs on boot, logs warnings if mismatched
- **Settlement**: Settler auto-closes → draws off-chain → syncs draw on-chain → pushes winners to vault + prize pool → reveals via PubSub
- **Block hash**: Settler fetches from on-chain close or falls back to Rogue RPC
- **Prize registration**: Settler calls `airdrop_set_prize` (PrizePool, Arbitrum) + `airdrop_set_winner` (Vault, Rogue) for all 33 winners
- **On-chain verification**: Winners pushed via `setWinner()` are queryable via `getWinnerInfo(position)` on RogueScan
