# BUX Booster Bet Settlement Recovery

## Overview

The `BuxBoosterBetSettler` GenServer automatically monitors and settles BuxBooster bets that failed to settle due to temporary network issues, server restarts, or other transient failures.

## How It Works

### Periodic Checks
- Runs every **1 minute** (`@check_interval`)
- Queries Mnesia for bets with `status = :placed`
- Only attempts settlement for bets older than **30 seconds** (`@settlement_timeout`)
- This avoids race conditions with bets that just finished their game flow

### Settlement Logic
1. **Find Unsettled Bets**:
   ```elixir
   :mnesia.dirty_match_object({:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, ...})
   ```
   Finds all games with `:placed` status (bet was submitted on-chain but not settled)

2. **Filter by Age**:
   ```elixir
   created_at < cutoff_time  # cutoff_time = now - 30_seconds
   ```
   Only processes bets that are at least 30 seconds old

3. **Attempt Settlement**:
   - Calls `BuxBoosterOnchain.settle_game(game_id)` for each stuck bet
   - This handles the full settlement flow (HTTP call to BUX Minter, Mnesia update)
   - Logs success or failure for each attempt
   - Handles exceptions gracefully

   **Note**: The settler uses `BuxBoosterOnchain.settle_game/1` (not `BuxMinter.settle_bet/4` which doesn't exist). This was fixed on Dec 30, 2024.

### What Gets Settled
Bets in `:placed` status means:
- Commitment was submitted on-chain ✓
- `placeBet()` or `placeBetROGUE()` transaction confirmed ✓
- Game results calculated ✓
- Settlement transaction **failed or never sent** ❌

Common reasons for stuck bets:
- BUX Minter API timeout during settlement
- Network interruption mid-settlement
- Phoenix server restarted before settlement completed
- BUX Minter deployment during active game

## Mnesia Table Structure

The settler reads from `:bux_booster_onchain_games`:

```elixir
{:bux_booster_onchain_games,
  game_id,           # 1
  user_id,           # 2
  wallet_address,    # 3
  server_seed,       # 4 - revealed after bet placed
  commitment_hash,   # 5 - on-chain commitment ID
  nonce,             # 6
  status,            # 7 - :pending | :committed | :placed | :settled
  bet_id,            # 8
  token,             # 9
  token_address,     # 10
  bet_amount,        # 11
  difficulty,        # 12
  predictions,       # 13
  results,           # 14 - calculated after bet placed
  won,               # 15 - boolean
  payout,            # 16
  commitment_tx,     # 17
  bet_tx,            # 18
  settlement_tx,     # 19
  created_at,        # 20 - timestamp when bet was placed
  settled_at         # 21
}
```

The settler extracts:
- `game_id` (element 1)
- `user_id` (element 2)
- `commitment_hash` (element 5) - identifies the bet on-chain
- `server_seed` (element 4) - revealed seed for settlement
- `results` (element 14) - game outcome
- `won` (element 15) - win/loss boolean
- `created_at` (element 20) - for age filtering

## Logging

### Startup
```
[BetSettler] Starting bet settlement checker (runs every minute)
```

### Found Unsettled Bets
```
[BetSettler] Found 3 unsettled bets older than 30 seconds
[BetSettler] Attempting to settle bet abc123... (placed 45s ago)
```

### Settlement Results
```
# Success
[BetSettler] ✅ Successfully settled bet abc123...: %{tx_hash: "0x...", payout: 100}

# Failure
[BetSettler] ❌ Failed to settle bet abc123...: {:error, "HTTP 500"}

# Exception
[BetSettler] ❌ Exception settling bet abc123...: %RuntimeError{...}
```

## Configuration

Edit `lib/blockster_v2/bux_booster_bet_settler.ex`:

```elixir
@check_interval :timer.minutes(1)      # How often to check
@settlement_timeout 30_000             # Min age before settling (ms)
```

## Supervision

Added to `BlocksterV2.Application` supervision tree:

```elixir
children = [
  # ...
  {BlocksterV2.BuxBoosterBetSettler, []},
  BlocksterV2Web.Endpoint
]
```

Restarts automatically if it crashes (`:one_for_one` strategy).

## Manual Triggering

To manually trigger a settlement check in IEx:

```elixir
# Send the check message directly
send(BlocksterV2.BuxBoosterBetSettler, :check_unsettled_bets)
```

## Deployment

The settler runs on all nodes in the cluster. This is **safe** because:
- Settlement is idempotent (BUX Minter/contract handle duplicate settlement attempts)
- First successful settlement marks bet as `:settled`
- Subsequent attempts skip it (status filter)

## Testing

### Create a Stuck Bet (for testing only)
1. Place a bet normally
2. Before settlement completes, stop the BUX Minter service
3. Bet will remain in `:placed` status
4. Wait 1 minute - BetSettler will attempt to settle it
5. Restart BUX Minter - settlement should succeed

### Check Logs
```bash
# Production (Fly.io)
flyctl logs --app blockster-v2 | grep BetSettler

# Development
# Watch console output for [BetSettler] messages
```

## Future Enhancements

Potential improvements:
- [ ] Max retry limit (e.g., give up after 10 attempts)
- [ ] Exponential backoff for failed settlements
- [ ] Admin dashboard showing stuck bets
- [ ] Alerts when bets remain unsettled for >1 hour
- [ ] Metrics tracking (settlement success rate, average retry count)

## Security Considerations

- **No user input**: Settler only processes existing Mnesia data
- **Server-side only**: Results already calculated and stored
- **Idempotent**: Duplicate settlement attempts are harmless
- **Authorized**: Uses server's BUX Minter credentials (no user auth bypass)

## Performance Impact

- **Query cost**: 1 Mnesia dirty operation per minute (fast)
- **Settlement cost**: N API calls where N = stuck bets (typically 0)
- **Memory**: Negligible (GenServer state is empty map)
- **CPU**: Minimal (only active when stuck bets exist)

Expected load: ~0 most of the time, spikes only during BUX Minter outages.

## Cleaning Up Orphaned Bets

Sometimes bets get stuck in `:placed` status because they exist in Mnesia but not on-chain (e.g., bet was created locally but never submitted to blockchain). These will fail settlement with errors like:
- `BetNotFound()` (0x469bfa91) - Bet doesn't exist on-chain
- `BetExpiredError()` (0xb3679761) - Bet exists but has expired

### Identify Orphaned Bets

```elixir
# Save as /tmp/find_orphaned.exs
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)

games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])

# Filter to very old bets (>1 hour)
cutoff = System.system_time(:millisecond) - (60 * 60 * 1000)
orphaned = Enum.filter(games, fn g -> elem(g, 20) < cutoff end)

IO.puts("Found #{length(orphaned)} orphaned bets")
for g <- orphaned do
  age_hours = div(System.system_time(:millisecond) - elem(g, 20), 3600000)
  IO.puts("  Game #{elem(g, 1)} - #{age_hours} hours old")
end
```

Run: `elixir --sname find$RANDOM /tmp/find_orphaned.exs`

### Expire Orphaned Bets

```elixir
# Save as /tmp/expire_orphaned.exs
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)

games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])

cutoff = System.system_time(:millisecond) - (60 * 60 * 1000)
orphaned = Enum.filter(games, fn g -> elem(g, 20) < cutoff end)

IO.puts("Expiring #{length(orphaned)} orphaned bets")
for g <- orphaned do
  updated = put_elem(g, 7, :expired)  # Change status to :expired
  :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_write, [updated])
  IO.puts("  Expired: #{elem(g, 1)}")
end
```

Run: `elixir --sname expire$RANDOM /tmp/expire_orphaned.exs`

### Verify Cleanup

```elixir
# Check remaining :placed bets
games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])
IO.puts("Remaining :placed bets: #{length(games)}")
```

See also: [docs/mnesia_remote_access.md](mnesia_remote_access.md) for detailed RPC patterns.
