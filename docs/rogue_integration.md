# ROGUE Token Integration

**Created**: December 2024
**Status**: Active

## Overview

ROGUE is the native gas token of Rogue Chain (similar to ETH on Ethereum). Unlike BUX and hub tokens which are ERC-20 tokens, ROGUE is built into the blockchain itself. This document explains how ROGUE is integrated into the Blockster platform.

---

## Key Differences: ROGUE vs BUX Tokens

| Aspect | ROGUE | BUX/Hub Tokens |
|--------|-------|----------------|
| **Token Type** | Native gas token | ERC-20 tokens |
| **Contract Address** | None (part of blockchain) | Has contract address |
| **Balance Checking** | `provider.getBalance(address)` | ERC-20 `balanceOf()` |
| **Transfer Method** | Direct value transfer `{value: amountWei}` | `approve()` + `transferFrom()` |
| **Multi-Chain** | Rogue Chain (native) + Arbitrum One (ERC-20) | Rogue Chain only |
| **Aggregate Calculation** | NOT included in BUX aggregate | Included in aggregate |
| **Mnesia Storage** | Separate `user_rogue_balances` table | Stored in `user_bux_balances` |

---

## Architecture

### 1. Multi-Chain Support

ROGUE exists on two chains with different implementations:

#### Rogue Chain (Mainnet - Chain ID: 560013)
- **Type**: Native gas token
- **Purpose**: Pay for transaction fees
- **How to get balance**: `provider.getBalance(address)` - returns native token balance in wei
- **How to transfer**: Include value directly in transaction: `{value: ethers.parseUnits(amount, 18)}`
- **Decimals**: 18
- **Use in platform**: Gaming (BUX Booster), payments, gas fees

#### Arbitrum One
- **Type**: ERC-20 token (bridged ROGUE)
- **Purpose**: Trading, liquidity pools (Uniswap)
- **How to get balance**: Standard ERC-20 `balanceOf(address)`
- **How to transfer**: Standard ERC-20 `approve()` + `transferFrom()`
- **Contract**: TBD (not yet deployed/tracked)
- **Use in platform**: Future - allow users to view Arbitrum ROGUE holdings

---

## Implementation Details

### Backend: BUX Minter Service

**File**: `bux-minter/index.js`

The BUX Minter service fetches ROGUE balance separately from ERC-20 tokens:

```javascript
// Get all token balances via BalanceAggregator contract (single RPC call)
// Also fetches ROGUE (native token) balance separately
app.get('/aggregated-balances/:address', authenticate, async (req, res) => {
  const { address } = req.params;

  try {
    // Fetch ROGUE (native token) balance using provider.getBalance()
    const rogueBalanceWei = await provider.getBalance(address);
    const rogueBalance = parseFloat(ethers.formatUnits(rogueBalanceWei, 18));

    // Call the aggregator contract - returns array of uint256 balances for ERC-20 tokens
    const rawBalances = await balanceAggregator.getBalances(address, TOKEN_ADDRESSES);

    // Convert to formatted balances map (all tokens have 18 decimals)
    const balances = { ROGUE: rogueBalance }; // Add ROGUE first
    let aggregate = 0;

    for (let i = 0; i < TOKEN_ORDER.length && i < rawBalances.length; i++) {
      const tokenName = TOKEN_ORDER[i];
      const formatted = parseFloat(ethers.formatUnits(rawBalances[i], 18));
      balances[tokenName] = formatted;
      aggregate += formatted; // Only BUX tokens count toward aggregate (not ROGUE)
    }

    res.json({
      address,
      balances,
      aggregate
    });
  } catch (error) {
    console.error(`[AGGREGATED] Error getting balances:`, error);
    res.status(500).json({ error: 'Failed to get aggregated balances', details: error.message });
  }
});
```

**Key Points**:
- ROGUE balance fetched first using `provider.getBalance()`
- ROGUE added to balances map BEFORE ERC-20 tokens
- ROGUE **excluded** from aggregate calculation
- Aggregate only includes BUX and hub tokens

---

### Database: Mnesia Storage

**File**: `lib/blockster_v2/mnesia_initializer.ex`

ROGUE has its own dedicated Mnesia table (separate from BUX tokens):

```elixir
%{
  name: :user_rogue_balances,
  type: :set,
  attributes: [
    :user_id,                   # Primary key
    :user_smart_wallet,         # User's smart wallet address
    :updated_at,                # Last update timestamp
    :rogue_balance_rogue_chain, # ROGUE balance on Rogue Chain (native token)
    :rogue_balance_arbitrum     # ROGUE balance on Arbitrum One (ERC-20 token)
  ],
  index: [:user_smart_wallet]
}
```

**Why a separate table?**
1. ROGUE is fundamentally different (native vs ERC-20)
2. Supports multiple chains (Rogue Chain + Arbitrum)
3. Not included in BUX aggregate calculations
4. Avoids breaking existing `user_bux_balances` table schema

**Table Structure**:
| Position | Field | Type | Description |
|----------|-------|------|-------------|
| 0 | :user_rogue_balances | atom | Table name |
| 1 | user_id | integer | Primary key |
| 2 | user_smart_wallet | string | Wallet address |
| 3 | updated_at | integer | Unix timestamp |
| 4 | rogue_balance_rogue_chain | float | Rogue Chain balance |
| 5 | rogue_balance_arbitrum | float | Arbitrum balance (future) |

---

### Phoenix Backend: EngagementTracker

**File**: `lib/blockster_v2/engagement_tracker.ex`

#### Update ROGUE Balance

```elixir
@doc """
Updates ROGUE balance for a user (supports both Rogue Chain and Arbitrum).
For now, only Rogue Chain is fetched by BuxMinter.
"""
def update_user_rogue_balance(user_id, wallet_address, balance, chain \\ :rogue_chain) do
  now = System.system_time(:second)
  balance_float = parse_balance(balance)

  case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
    [] ->
      # Create new record
      record = case chain do
        :rogue_chain ->
          {:user_rogue_balances, user_id, wallet_address, now, balance_float, 0.0}
        :arbitrum ->
          {:user_rogue_balances, user_id, wallet_address, now, 0.0, balance_float}
      end
      :mnesia.dirty_write(record)
      {:ok, balance_float}

    [existing] ->
      # Update existing record
      field_index = case chain do
        :rogue_chain -> 4  # rogue_balance_rogue_chain
        :arbitrum -> 5     # rogue_balance_arbitrum
      end

      updated = existing
        |> put_elem(2, wallet_address)       # user_smart_wallet
        |> put_elem(3, now)                   # updated_at
        |> put_elem(field_index, balance_float)

      :mnesia.dirty_write(updated)
      {:ok, balance_float}
  end
end
```

#### Get All Token Balances (Including ROGUE)

```elixir
def get_user_token_balances(user_id) do
  # Get BUX token balances (from user_bux_balances table)
  bux_balances = case :mnesia.dirty_read({:user_bux_balances, user_id}) do
    [] ->
      %{
        "aggregate" => 0.0,
        "BUX" => 0.0,
        "moonBUX" => 0.0,
        # ... other BUX tokens
      }
    [record] ->
      %{
        "aggregate" => elem(record, 4) || 0.0,
        "BUX" => elem(record, 5) || 0.0,
        # ... other BUX tokens
      }
  end

  # Get ROGUE balance (from user_rogue_balances table)
  rogue_balance = case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
    [] -> 0.0
    [rogue_record] -> elem(rogue_record, 4) || 0.0  # rogue_balance_rogue_chain
  end

  # Merge ROGUE balance into the map
  Map.put(bux_balances, "ROGUE", rogue_balance)
end
```

**Note**: Currently only Rogue Chain balance is fetched. Arbitrum support planned for future.

---

### Frontend: Token Dropdown Display

**File**: `lib/blockster_v2_web/components/layouts.ex`

The top-right token dropdown displays ROGUE at the top, then BUX, then other tokens:

```elixir
<!-- Token Balances -->
<%= if assigns[:token_balances] && map_size(@token_balances) > 0 do %>
  <div class="border-t border-gray-100 py-1">
    <%
      # Always show ROGUE and BUX at top, then other tokens with balance > 0
      rogue_balance = Map.get(@token_balances, "ROGUE", 0)
      bux_balance = Map.get(@token_balances, "BUX", 0)
      other_tokens = Enum.filter(@token_balances, fn {k, v} ->
        k not in ["aggregate", "ROGUE", "BUX"] && is_number(v) && v > 0
      end) |> Enum.sort_by(fn {_, v} -> v end, :desc)

      display_tokens = [{"ROGUE", rogue_balance}, {"BUX", bux_balance}] ++ other_tokens
    %>
    <%= for {token_name, balance} <- display_tokens do %>
      <div class="flex items-center justify-between px-4 py-1.5 text-xs text-gray-600">
        <!-- Token logo and name -->
        <!-- Balance display -->
      </div>
    <% end %>
```

**Display Order**:
1. **ROGUE** - Always first (even if 0 balance)
2. **BUX** - Always second (even if 0 balance)
3. **Other tokens** - Only if balance > 0, sorted by balance descending

**Buy Link**:
If ROGUE balance is 0, a "Buy" link appears pointing to Uniswap pool on Arbitrum:
```elixir
<%= if token == "ROGUE" and Map.get(@balances, "ROGUE", 0) == 0 do %>
  <a href="https://app.uniswap.org/explore/pools/arbitrum/..." target="_blank">Buy</a>
<% end %>
```

---

### BUX Booster Game Integration

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

#### Token Selection

BUX Booster only allows ROGUE and BUX tokens (hub tokens removed):

```elixir
# Only allow ROGUE and BUX tokens, with ROGUE first
tokens = ["ROGUE", "BUX"]
```

**Token Dropdown**:
- ROGUE appears first
- BUX appears second
- Selection color changed from purple to grey
- Displays token logo, bet amount, and token name

#### Future: ROGUE Betting Optimization

When ROGUE betting is implemented, it will have advantages over BUX:

**BUX Betting** (ERC-20):
1. User calls `approve(gameContract, betAmount)` → UserOperation 1
2. User calls `placeBet(betAmount, predictions, ...)` → UserOperation 2
3. **Total**: 2 UserOperations, ~4-5 seconds

**ROGUE Betting** (Native Token):
1. User calls `placeBet(predictions, ...)` with `{value: betAmount}` → UserOperation 1
2. **Total**: 1 UserOperation, ~2-3 seconds
3. **50% faster** - no approval needed!

---

## Data Flow

### 1. Balance Sync on Page Load

```
User loads page (connected mount)
  ↓
BuxBoosterLive.mount/3
  ↓
BuxMinter.sync_user_balances_async(user_id, wallet_address)
  ↓
BuxMinter.get_aggregated_balances(wallet_address)
  ↓
HTTP GET /aggregated-balances/:address
  ↓
BUX Minter Service:
  - provider.getBalance(address) → ROGUE balance
  - balanceAggregator.getBalances(address, tokens) → ERC-20 balances
  - Returns: {balances: {...}, aggregate: XXX}
  ↓
BuxMinter.sync_user_balances/2
  ↓
For each token in balances:
  - If token == "ROGUE":
      EngagementTracker.update_user_rogue_balance(user_id, wallet, balance)
        → Writes to :user_rogue_balances Mnesia table
  - Else:
      EngagementTracker.update_user_token_balance(user_id, wallet, token, balance)
        → Writes to :user_bux_balances Mnesia table
  ↓
BuxBalanceHook.broadcast_token_balances_update(user_id, balances)
  ↓
All subscribed LiveViews receive {:token_balances_updated, balances}
  ↓
UI updates with new balances
```

### 2. Balance Display

```
Header renders
  ↓
BuxBalanceHook intercepts mount
  ↓
EngagementTracker.get_user_token_balances(user_id)
  ↓
Reads from two Mnesia tables:
  - :user_bux_balances → BUX, moonBUX, neoBUX, etc.
  - :user_rogue_balances → ROGUE (Rogue Chain)
  ↓
Returns merged map:
  {
    "aggregate" => 1234.56,  # Sum of BUX tokens only
    "ROGUE" => 5.0,          # Separate, not in aggregate
    "BUX" => 800.0,
    "moonBUX" => 434.56,
    ...
  }
  ↓
Assigns to socket as :token_balances
  ↓
Template displays:
  - Top aggregate: "1,234.56 BUX" (excludes ROGUE)
  - Dropdown: ROGUE (5.0), BUX (800.0), moonBUX (434.56), ...
```

---

## Important Design Decisions

### 1. Why Separate Mnesia Table?

**Options Considered**:
- ❌ **Add ROGUE field to `user_bux_balances`**: Would require schema migration, production downtime, and field would be in the middle (not allowed - must append to end)
- ✅ **Create new `user_rogue_balances` table**: Clean separation, supports multi-chain, no migration needed

**Benefits of Separate Table**:
- No risk of corrupting existing BUX balance data
- Clearly separates native token from ERC-20 tokens
- Supports future multi-chain expansion (Arbitrum)
- Simpler to query and reason about
- Development: just restart nodes to create table

### 2. Why Exclude ROGUE from Aggregate?

**Reasoning**:
- Aggregate represents "total BUX holdings" - a unified measure of BUX tokens
- ROGUE is fundamentally different (native gas token, not a BUX flavor)
- Users care about "How much BUX do I have?" separately from "How much ROGUE do I have?"
- Mixing native gas tokens with utility tokens creates confusion
- Aggregate calculation: `BUX + moonBUX + neoBUX + ... (all ERC-20 BUX tokens)`

**Display Strategy**:
- Aggregate shown as "BUX Balances: X,XXX.XX BUX"
- ROGUE shown separately in dropdown
- Clear visual distinction in UI

### 3. Why ROGUE First in Dropdown?

**User Experience**:
- ROGUE is the native token of the chain - most fundamental
- Users need ROGUE to pay gas fees
- Primary currency for most users
- BUX is secondary (rewards, in-app currency)
- Natural ordering: native token → platform token → hub tokens

---

## Testing ROGUE Integration

### 1. Check Balance Fetching

```bash
# In Phoenix console (iex -S mix)
user_id = 1
wallet = "0x..."

# Trigger balance sync
BuxMinter.sync_user_balances(user_id, wallet)

# Check Mnesia tables
:mnesia.dirty_read({:user_rogue_balances, user_id})
# Should return: {:user_rogue_balances, 1, "0x...", timestamp, 5.0, 0.0}

:mnesia.dirty_read({:user_bux_balances, user_id})
# Should return BUX token balances (ROGUE not included)
```

### 2. Verify Aggregate Calculation

```elixir
# Get all balances
balances = EngagementTracker.get_user_token_balances(user_id)

# Check structure
balances["ROGUE"]      # Should be ROGUE balance from Rogue Chain
balances["BUX"]        # Should be BUX balance
balances["aggregate"]  # Should NOT include ROGUE balance

# Verify aggregate = sum of BUX tokens only
total_bux = balances["BUX"] + balances["moonBUX"] + balances["neoBUX"] + ...
total_bux == balances["aggregate"]  # Should be true
```

### 3. Test Frontend Display

1. Load `/play` page
2. Check top-right dropdown
3. Verify order: ROGUE → BUX → other tokens
4. Verify aggregate excludes ROGUE
5. Verify ROGUE shows even with 0 balance
6. If ROGUE balance is 0, verify "Buy" link appears

---

## Future Enhancements

### 1. Arbitrum ROGUE Balance

**Status**: Mnesia table ready, fetching not implemented

**TODO**:
- Add Arbitrum RPC to BUX Minter
- Query ROGUE ERC-20 contract on Arbitrum
- Store in `rogue_balance_arbitrum` field
- Display combined balance: `rogue_chain + arbitrum`

**Code**:
```javascript
// In BUX Minter
const arbitrumProvider = new ethers.JsonRpcProvider(ARBITRUM_RPC);
const rogueTokenArbitrum = new ethers.Contract(ROGUE_ARBITRUM_ADDRESS, ERC20_ABI, arbitrumProvider);
const arbBalance = await rogueTokenArbitrum.balanceOf(address);
```

### 2. ROGUE Betting in BUX Booster

**Status**: Not implemented

**Advantages**:
- No approval needed (native token)
- Single UserOperation instead of two
- ~50% faster than BUX betting
- Better UX

**Implementation**:
- Detect selected token in frontend
- If ROGUE: send value in transaction, skip approval
- If BUX: current approve + placeBet flow

### 3. ROGUE Rewards

**Status**: Not implemented

**Consideration**: Should users earn ROGUE for reading articles?
- **Pro**: Native token has more universal value
- **Con**: Gas token should be acquired, not freely distributed
- **Decision**: Keep BUX as rewards token, ROGUE for purchases/betting

---

## Configuration

### Environment Variables

**BUX Minter** (`.env`):
```bash
RPC_URL=https://rpc.roguechain.io/rpc  # Rogue Chain Mainnet RPC
```

No special configuration needed for ROGUE - it's automatically available via the RPC provider.

### Contract Addresses

**Rogue Chain**:
- ROGUE: Native token (no contract address)
- All BUX tokens: See `TOKEN_CONTRACTS` in `bux-minter/index.js`

**Arbitrum One** (future):
- ROGUE ERC-20: TBD

---

## Deployment Notes

### Production Deployment Checklist

When deploying ROGUE integration to production:

1. ✅ Deploy BUX Minter first (already done)
   ```bash
   cd bux-minter
   flyctl deploy --app bux-minter
   ```

2. ⚠️ **CRITICAL**: Scale down to 1 machine before deploying Phoenix app
   ```bash
   flyctl scale count 1 --app blockster-v2
   ```

3. Deploy Phoenix app with new Mnesia table
   ```bash
   git push origin main
   flyctl deploy --app blockster-v2
   ```

4. Wait for Mnesia table creation (check logs for "Creating Mnesia table: user_rogue_balances")

5. Scale back up to 2 machines
   ```bash
   flyctl scale count 2 --app blockster-v2
   ```

6. Monitor logs for "user_rogue_balances" sync messages

### Development Setup

**New Mnesia Table**:
When you add a new Mnesia table in development:

1. Delete existing Mnesia directories:
   ```bash
   rm -rf priv/mnesia/node1 priv/mnesia/node2
   ```

2. Restart both nodes:
   ```bash
   # Terminal 1
   elixir --sname node1 -S mix phx.server

   # Terminal 2
   PORT=4001 elixir --sname node2 -S mix phx.server
   ```

3. Tables will be created on startup
4. Node2 will automatically sync with Node1

---

## Troubleshooting

### ROGUE Balance Not Showing

**Check**:
1. BUX Minter is deployed and running
2. User has wallet connected
3. Balance sync was triggered on page load
4. Mnesia table exists: `:mnesia.system_info(:tables)` includes `:user_rogue_balances`
5. Check BUX Minter logs for "Fetching balances for..." message
6. Check Phoenix logs for "Created user_rogue_balances" or "Updated user_rogue_balances"

**Fix**:
```bash
# Trigger manual sync
BuxMinter.sync_user_balances(user_id, wallet_address)
```

### Unknown Token Warning

If you see: `[warning] [EngagementTracker] Unknown token 'ROGUE' - skipping balance update`

This should not happen after the fix. If it does:
1. Check that `update_user_token_balance/4` has the ROGUE check at the top
2. Restart Phoenix servers
3. Clear Mnesia and restart

### Aggregate Including ROGUE

If aggregate incorrectly includes ROGUE balance:

**Check**:
1. BUX Minter `/aggregated-balances` endpoint - should exclude ROGUE from aggregate
2. Frontend aggregate calculation - should not include ROGUE
3. `calculate_aggregate_balance/1` in EngagementTracker - should only sum BUX tokens

---

## Summary

ROGUE is now fully integrated into Blockster with:

✅ **Multi-chain support**: Rogue Chain (native) + Arbitrum (ERC-20, future)
✅ **Separate storage**: Dedicated Mnesia table for clean separation
✅ **Excluded from aggregate**: Maintains BUX aggregate purity
✅ **Prioritized in UI**: Always shown first in token dropdown
✅ **Ready for gaming**: Available in BUX Booster token selector
✅ **Optimized fetching**: Uses native `getBalance()` for Rogue Chain
✅ **Well documented**: This file + CLAUDE.md + code comments

The integration respects ROGUE's unique nature as a native gas token while seamlessly incorporating it into the platform's token display and management systems.
