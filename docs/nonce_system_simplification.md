# Nonce System Simplification (Dec 2024)

## Problem

The BUX Booster game was experiencing nonce synchronization issues between Mnesia (server state) and the smart contract, causing `CommitmentWrongNonce` errors (0x5a01a0a4).

**Original flow:**
1. Contract maintained `playerNonces[address]` mapping
2. Server set nonce via `submitCommitment(hash, player, nonce)`
3. Contract validated `commitment.nonce == playerNonces[msg.sender]` in `placeBet()`
4. Server queried contract on page load to sync Mnesia with blockchain state
5. **Issue**: Race conditions and stale data caused mismatches

## Solution

Completely removed nonce validation from the contract. Mnesia is now the single source of truth.

### Contract Changes

**File**: `contracts/bux-booster-game/contracts/BuxBoosterGame.sol`

1. **Removed nonce parameter from `placeBet()`** (line 628)
   ```solidity
   // BEFORE
   function placeBet(..., bytes32 commitmentHash, uint256 nonce)

   // AFTER
   function placeBet(..., bytes32 commitmentHash)
   ```

2. **Removed nonce validation** (line 656)
   ```solidity
   // BEFORE
   if (commitment.nonce != playerNonces[msg.sender]) revert CommitmentWrongNonce();

   // AFTER
   // Note: Nonce is NOT validated - server manages nonces in Mnesia
   ```

3. **Removed playerNonces update** (line 601)
   ```solidity
   // BEFORE
   playerNonces[player] = nonce;

   // AFTER
   // (removed - no longer updating this mapping)
   ```

4. **KEPT the mapping variable** (line 436) for storage layout safety
   ```solidity
   mapping(address => uint256) public playerNonces;  // Unused but preserved
   ```

### Backend Changes

**File**: `lib/blockster_v2/bux_booster_onchain.ex`

1. **Removed contract nonce queries** (deleted `get_onchain_player_nonce/1` function)
2. **Simplified `get_or_init_game/2`** (line 329)
   - Calculates next nonce purely from Mnesia
   - Finds max nonce from placed/settled bets
   - Increments by 1 for next game
   - Never queries blockchain

```elixir
def get_or_init_game(user_id, wallet_address) do
  # Calculate next nonce from Mnesia based on placed bets
  next_nonce = case :mnesia.dirty_match_object({:bux_booster_onchain_games, ...}) do
    [] -> 0  # No games yet
    games ->
      placed_games = Enum.filter(games, fn game ->
        elem(game, 7) in [:placed, :settled]
      end)

      case placed_games do
        [] -> 0  # No placed bets yet
        _ ->
          # Max nonce from placed bets + 1
          placed_games
          |> Enum.map(fn game -> elem(game, 6) end)
          |> Enum.max()
          |> Kernel.+(1)
      end
  end

  # Create or reuse commitment with calculated nonce
  init_game_with_nonce(user_id, wallet_address, next_nonce)
end
```

### Frontend Changes

**File**: `assets/js/bux_booster_onchain.js`

1. **Removed nonce from contract calls** (lines 216, 266)
   ```javascript
   // BEFORE
   method: "function placeBet(..., bytes32 commitmentHash, uint256 nonce)",
   params: [..., commitmentHash, this.nonce]

   // AFTER
   method: "function placeBet(..., bytes32 commitmentHash)",
   params: [..., commitmentHash]
   ```

2. **Removed nonce storage in hook** (line 48)
   ```javascript
   // BEFORE
   this.nonce = nonce;

   // AFTER
   // (removed - not needed for contract calls)
   ```

### LiveView Changes

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

1. **Removed "Play Again" distinction** (line 1156)
   - Both page load and "Play Again" now call same function
   - `get_or_init_game/2` handles both cases
   - No async contract queries

```elixir
# Both mount and reset_game use the same function
case BuxBoosterOnchain.get_or_init_game(current_user.id, wallet_address) do
  {:ok, game_session} -> ...
end
```

## How It Works Now

### First Game
1. User loads `/play` page
2. Mnesia: No games found → nonce = 0
3. Server submits commitment with nonce 0
4. Player places bet
5. Contract accepts bet (no nonce validation)
6. Bet settled, game marked as `:settled` in Mnesia

### Second Game ("Play Again")
1. User clicks "Play Again"
2. Mnesia: Finds game with nonce 0 (status `:settled`)
3. Max nonce = 0, next nonce = 0 + 1 = 1
4. Server submits commitment with nonce 1
5. Player places bet
6. Contract accepts bet (no nonce validation)

### Key Points

- **No contract queries**: Mnesia never asks blockchain for nonces
- **No sync issues**: Mnesia is the only source of truth
- **No validation errors**: Contract accepts all valid commitments regardless of nonce
- **Nonces still tracked**: Used internally by Mnesia for game session management
- **Provably fair**: Commitment-reveal pattern still intact

## Benefits

1. **Eliminated nonce sync issues**: No more `CommitmentWrongNonce` errors
2. **Faster page loads**: No blockchain RPC calls on page load
3. **Simpler code**: Removed contract querying logic
4. **Same security**: Commitment-reveal pattern unchanged
5. **Backward compatible**: Nonce still stored in commitment struct for reference

## Trade-offs

**What we gave up:**
- Contract-enforced nonce ordering (wasn't working anyway due to sync issues)

**What we gained:**
- Reliability: No failed bets due to nonce mismatches
- Performance: Faster game initialization
- Simplicity: Less code, fewer failure modes

## Deployment

**Date**: December 28, 2024

**Contract Upgrade**:
- Proxy: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (unchanged)
- New Implementation: `0x766B68bf3CB02C19296c8e8e7C1394bb51ab5e6B`
- Upgrade Method: Manual via `upgradeToAndCall()` with explicit gas limit

**Backend Deployment**:
- No database migrations needed
- Mnesia tables unchanged
- Existing games continue to work

## Testing Checklist

After deployment, verify:
- [ ] First game starts with nonce 0
- [ ] Second game increments to nonce 1
- [ ] Page loads quickly (no contract queries)
- [ ] "Play Again" works without errors
- [ ] No `CommitmentWrongNonce` errors in logs
- [ ] Bets settle correctly
- [ ] Provably fair verification still works

## Code References

- Contract: [`contracts/bux-booster-game/contracts/BuxBoosterGame.sol`](../contracts/bux-booster-game/contracts/BuxBoosterGame.sol)
  - Line 436: `playerNonces` mapping (unused but preserved)
  - Line 601: Removed `playerNonces[player] = nonce`
  - Line 656: Removed nonce validation
  - Line 628: Removed nonce parameter from `placeBet()`

- Backend: [`lib/blockster_v2/bux_booster_onchain.ex`](../lib/blockster_v2/bux_booster_onchain.ex)
  - Line 329: `get_or_init_game/2` - nonce calculation from Mnesia
  - Line 61: `init_game_with_nonce/3` - unchanged

- Frontend: [`assets/js/bux_booster_onchain.js`](../assets/js/bux_booster_onchain.js)
  - Line 216: Batch transaction without nonce
  - Line 266: Single transaction without nonce

- LiveView: [`lib/blockster_v2_web/live/bux_booster_live.ex`](../lib/blockster_v2_web/live/bux_booster_live.ex)
  - Line 53: Async game init on mount
  - Line 1156: "Play Again" using same function

## Related Documentation

- [Contract Upgrades](./contract_upgrades.md) - How to upgrade BuxBoosterGame
- [BUX Booster On-chain](./bux_booster_onchain.md) - Game architecture
- [Provably Fair System](./provably_fair.md) - Commitment-reveal pattern
