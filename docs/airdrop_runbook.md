# Airdrop Runbook — Operating Guide

Step-by-step instructions to fund, activate, run, and settle an airdrop round.

## Prerequisites

- [ ] AirdropVault deployed on Rogue Chain: `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c`
- [ ] AirdropPrizePool deployed on Arbitrum One: `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1`
- [ ] BUX Minter deployed to `bux-minter.fly.dev` with `VAULT_ADMIN_PRIVATE_KEY` secret set
- [ ] Vault Admin wallet (`0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`) has ETH on both Rogue and Arbitrum for gas
- [ ] USDT funded into PrizePool contract (at least $2,000 for a full round)
- [ ] `VAULT_ADMIN_PRIVATE_KEY` in `contracts/bux-booster-game/.env` (for hardhat scripts)

---

## Contract Addresses

| Contract | Chain | Address |
|----------|-------|---------|
| AirdropVault (Proxy) | Rogue Chain (560013) | `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c` |
| AirdropPrizePool (Proxy) | Arbitrum One (42161) | `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1` |
| BUX Token | Rogue Chain | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` |
| USDT | Arbitrum One | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| Vault Admin | Both | `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` |

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

## Phase 2: Start On-Chain Round (AirdropVault)

This registers the commitment hash on-chain before deposits start.

**Not yet automated** — needs a hardhat script. Run from IEx for now:

```elixir
# On the Elixir server (IEx or remote console)
alias BlocksterV2.Airdrop

# Choose end time (e.g., 7 days from now)
end_time = DateTime.add(DateTime.utc_now(), 7 * 86400, :second)
{:ok, round} = Airdrop.create_round(end_time)

# Note these values — you'll need them
round.round_id          # e.g., 1
round.commitment_hash   # SHA256 of server_seed
round.server_seed       # SECRET — do NOT share until after draw
```

**On-chain** (TODO: create script `start-airdrop-round.js`):

The AirdropVault contract needs `startRound(commitmentHash, endTime)` called from vault admin. This publishes the commitment on-chain for provable fairness.

```
vault.startRound(round.commitment_hash, unix_end_time)
```

> **Note**: Currently the on-chain `startRound` is not called — the Elixir backend manages rounds independently. For full provable fairness, this should be called so the commitment is verifiable on RogueScan.

---

## Phase 3: Users Redeem BUX (Automatic)

Once the round is open, users go to `/airdrop` and redeem BUX:

1. User enters amount → clicks "Redeem X BUX"
2. LiveView calls `Airdrop.redeem_bux(user, amount, round_id)` → creates Entry in Postgres with position block
3. PubSub broadcasts updated entry count to all connected users
4. Receipt panel shows position block (#start–#end)

### What happens per deposit (current flow):

- **Postgres**: Entry record created with `start_position`, `end_position`, `amount`
- **Mnesia**: BUX balance deducted (via engagement system)
- **On-chain**: NOT YET WIRED — `BuxMinter.airdrop_deposit` exists but isn't called from LiveView

### What SHOULD happen per deposit (full flow, Phase 8 TODO):

- All the above, PLUS:
- BUX Minter mints BUX to vault contract → calls `depositFor()` → on-chain position block recorded
- Entry gets `deposit_tx` from the on-chain transaction

### Monitor

```elixir
# Check round stats
Airdrop.get_total_entries(round_id)
Airdrop.get_participant_count(round_id)
```

---

## Phase 4: Close the Round

When the countdown ends, close the round to stop deposits and capture a block hash.

### Elixir (required)

```elixir
alias BlocksterV2.Airdrop

# Get current block hash from Rogue Chain for randomness
# Use a recent block hash — this is the external entropy source
block_hash = "0x..."  # Get from RogueScan or RPC call

{:ok, closed} = Airdrop.close_round(round_id, block_hash)
closed.status  # => "closed"
```

### On-chain (for full provable fairness)

```
vault.closeAirdrop()  # captures blockhash(block.number - 1) on-chain
```

> **TODO**: Create script `close-airdrop-round.js` or add to minter

---

## Phase 5: Draw Winners

Draw 33 winners using provably fair algorithm.

### Elixir (required)

```elixir
alias BlocksterV2.Airdrop

{:ok, drawn} = Airdrop.draw_winners(round_id)
drawn.status  # => "drawn"

# Check winners
winners = Airdrop.get_winners(round_id)
length(winners)  # => 33

# Verify fairness
Airdrop.verify_fairness(round_id)  # => true
```

This:
1. Combines `server_seed + block_hash` → `keccak256` → combined seed
2. For each winner i (0–32): `keccak256(combined, i) % total_entries + 1` → winning position
3. Maps position to the entry that contains it → winner's wallet
4. Creates 33 Winner records with prize amounts
5. Broadcasts `:airdrop_drawn` via PubSub → all connected users see results instantly

### On-chain (for full provable fairness)

```
vault.drawWinners(server_seed)  # verifies sha256(seed) == commitment, selects winners on-chain
```

---

## Phase 6: Register Prizes on Arbitrum

After drawing winners in Elixir, register each prize on the AirdropPrizePool contract so they can be claimed.

### Via IEx (calls BUX Minter → Arbitrum)

```elixir
alias BlocksterV2.{Airdrop, BuxMinter}

winners = Airdrop.get_winners(round_id)

# Register all 33 prizes
for w <- winners do
  {:ok, _} = BuxMinter.airdrop_set_prize(
    round_id,
    w.winner_index,
    w.external_wallet,
    w.prize_usdt
  )
  IO.puts("Set prize #{w.winner_index}: $#{div(w.prize_usd, 100)} to #{w.external_wallet}")
end
```

This calls `POST /airdrop-set-prize` on the BUX Minter for each winner, which calls `setPrize(roundId, winnerIndex, winner, amount)` on the PrizePool contract.

### Verify

```
# On Arbiscan, read PrizePool contract:
# getPrize(roundId, 0) → should show 1st place winner + 250_000_000 (=$250)
# getRoundPrizeTotal(roundId) → should show 2_000_000_000 (=$2000)
```

---

## Phase 7: Winners Claim Prizes (Automatic via UI)

Winners see their results on `/airdrop` and click "Claim" buttons.

### Current flow:

1. Winner clicks "Claim" → LiveView calls `Airdrop.claim_prize(user_id, round_id, winner_index, claim_tx, claim_wallet)`
2. Currently `claim_tx = "pending"` — does NOT call BuxMinter yet
3. Winner record updated with `claimed: true`

### Full flow (Phase 8 TODO — wire BuxMinter.airdrop_claim):

1. Winner clicks "Claim"
2. LiveView calls `BuxMinter.airdrop_claim(round_id, winner_index)`
3. BUX Minter calls `sendPrize(roundId, winnerIndex)` on Arbitrum PrizePool
4. USDT transferred to winner's external wallet
5. Returns Arbitrum tx hash → stored as `claim_tx`
6. Winner record updated with real tx hash

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

### Start new round on PrizePool (if running another round)

```
# On Arbitrum, call startNewRound() on PrizePool
# This increments the roundId so new prizes can be set
```

### Withdraw remaining BUX from vault (optional)

```
# On Rogue Chain, call withdrawBux(roundId) on AirdropVault
# Returns deposited BUX to vault admin
```

### Verify everything

```elixir
# Full verification
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

## Remaining TODOs for Full E2E

These items need to be wired before the airdrop is fully on-chain:

1. **Wire on-chain deposit**: LiveView `redeem_bux` should also call `BuxMinter.airdrop_deposit` after DB entry creation
2. **Wire on-chain claim**: LiveView `claim_prize` (line 159) should call `BuxMinter.airdrop_claim` and use real tx hash instead of `"pending"`
3. **Create `start-airdrop-round.js`**: Hardhat script to call `vault.startRound(commitmentHash, endTime)` — publishes commitment on-chain
4. **Create `close-airdrop-round.js`**: Hardhat script to call `vault.closeAirdrop()` — captures block hash on-chain
5. **Create `draw-airdrop-winners.js`**: Hardhat script to call `vault.drawWinners(serverSeed)` — runs provably fair draw on-chain
6. **Automate prize registration**: After `draw_winners`, automatically call `airdrop_set_prize` for all 33 winners
7. **Get real block hash**: `close_round` should fetch actual Rogue Chain block hash via RPC instead of manual input

### Can run without full on-chain integration

The airdrop works end-to-end in Postgres. The on-chain steps add provable fairness verification on RogueScan/Arbiscan but aren't required for the core flow. Prize payouts via `airdrop_claim` DO require the PrizePool to be funded and prizes registered.
