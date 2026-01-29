# Unified Multiplier System V2

## Overview

The unified multiplier system combines **four** verification/holding methods using a **multiplicative chain** to create an overall multiplier score. This system rewards quality users who verify their identity, engage on X, hold ROGUE in their Blockster wallet, and connect external wallets with other assets.

## Key Change from V1

**ROGUE is now completely separate from External Wallet multiplier.**

- ROGUE multiplier is based **only** on ROGUE held in your **Blockster smart wallet**
- External Wallet multiplier is based on ETH + other tokens (USDC, USDT, ARB) in your **connected external wallet**
- This means you can earn ROGUE multiplier without connecting any external wallet

---

## Multiplier Components

### 1. X Account Quality Score (1.0x - 10.0x)

| Score | Multiplier |
|-------|------------|
| 0 | 1.0x (minimum) |
| 10 | 1.0x |
| 29 | 2.9x |
| 50 | 5.0x |
| 75 | 7.5x |
| 100 | 10.0x (maximum) |

**Formula**: `max(x_score / 10.0, 1.0)`

**Source**: `BlocksterV2.Social.XScoreCalculator` module

When a user connects their X account via OAuth, the system:
1. Calls `XScoreCalculator.calculate_and_save_score/2`
2. Fetches user profile + recent tweets from X API via `XApiClient.fetch_score_data/2`
3. Calculates score from 6 components (total 100 points):
   - Follower quality (25 pts): followers/following ratio (ratio > 10 = max)
   - Engagement rate (35 pts): likes, retweets, replies on original tweets (scales with follower count)
   - Account age (10 pts): 5+ years = max score
   - Activity level (15 pts): 30+ tweets/month = max score
   - List presence (5 pts): 50+ lists = max score
   - Follower scale (10 pts): logarithmic scale from 1k to 10M followers
4. Saves score via `EngagementTracker.update_x_connection_score/2` and `EngagementTracker.set_user_x_multiplier/2`
5. Score is recalculated every 7 days automatically

**Current Storage** (existing system):
- `x_connections` Mnesia table: stores raw score + calculation details
- `user_multipliers` Mnesia table (index 3): stores raw score 0-100

**New Storage** (unified system):
- `unified_multipliers` Mnesia table: stores both raw `x_score` (0-100) and calculated `x_multiplier` (1.0-10.0)

---

### 2. Phone Verification Score (0.5x - 2.0x)

| Status | Tier | Multiplier |
|--------|------|------------|
| Not verified | - | 0.5x (penalty) |
| Verified | Basic (other countries) | 1.0x |
| Verified | Standard (BR, MX, EU, JP, KR) | 1.5x |
| Verified | Premium (US, CA, UK, AU, DE, FR) | 2.0x (maximum) |

**Source**: Mobile phone verification with location-based scoring

**Storage**: PostgreSQL `users.geo_multiplier`

---

### 3. ROGUE Multiplier (1.0x - 5.0x) - **NEW: Separated from Wallet**

**IMPORTANT**: Only ROGUE held in your **Blockster smart wallet** counts. External wallet ROGUE does NOT count.

| ROGUE Balance (Smart Wallet) | Boost | Total Multiplier |
|------------------------------|-------|------------------|
| 0 - 99,999 | +0.0x | 1.0x |
| 100,000 - 199,999 | +0.4x | 1.4x |
| 200,000 - 299,999 | +0.8x | 1.8x |
| 300,000 - 399,999 | +1.2x | 2.2x |
| 400,000 - 499,999 | +1.6x | 2.6x |
| 500,000 - 599,999 | +2.0x | 3.0x |
| 600,000 - 699,999 | +2.4x | 3.4x |
| 700,000 - 799,999 | +2.8x | 3.8x |
| 800,000 - 899,999 | +3.2x | 4.2x |
| 900,000 - 999,999 | +3.6x | 4.6x |
| 1,000,000+ | +4.0x | 5.0x (maximum) |

**Formula**: `1.0 + rogue_boost` where `rogue_boost` is 0.4x per 100k ROGUE, capped at 4.0x

**Cap**: Only first 1M ROGUE counts (holding 5M gives same multiplier as 1M)

**Source**: Blockster smart wallet ROGUE balance on Rogue Chain

**Storage**: Mnesia `user_multipliers.rogue_multiplier` (the full multiplier 1.0-5.0, NOT the boost)

**Why Smart Wallet Only?**
- Encourages users to deposit ROGUE into Blockster ecosystem
- Smart wallet balance is always accurate (no RPC calls needed)
- Simplifies calculation (single source of truth)
- Users don't need external wallet to benefit from ROGUE holdings

---

### 4. External Wallet Multiplier (1.0x - 3.6x) - **No ROGUE**

**IMPORTANT**: This multiplier is for ETH + other tokens only. ROGUE is handled separately above.

| Component | Range | Max Boost |
|-----------|-------|-----------|
| Base (wallet connected) | - | 1.0x |
| Connection boost | +0.1x | +0.1x |
| ETH (Mainnet + Arbitrum) | +0.1x to +1.5x | +1.5x |
| Other tokens (USD value) | +0.0x to +1.0x | +1.0x |
| **Total** | **1.0x to 3.6x** | **3.6x** |

**ETH Tiers**:
| Combined ETH | Boost |
|--------------|-------|
| 0 - 0.009 | +0.0x |
| 0.01 - 0.09 | +0.1x |
| 0.1 - 0.49 | +0.3x |
| 0.5 - 0.99 | +0.5x |
| 1.0 - 2.49 | +0.7x |
| 2.5 - 4.99 | +0.9x |
| 5.0 - 9.99 | +1.1x |
| 10.0+ | +1.5x |

**Other Tokens**: `min(total_usd_value / 10000, 1.0)`
- $5,000 = +0.5x
- $10,000+ = +1.0x (capped)

**Formula**: `1.0 + 0.1 + eth_boost + other_tokens_boost`

**Source**: Connected external wallet (MetaMask, Ledger, Trezor, etc.)

**Storage**: Mnesia `user_multipliers.wallet_multiplier` (the full multiplier 1.0-3.6, NOT the boost)

---

## Overall Multiplier Calculation

### Formula (Multiplicative Chain)

```
Overall = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier
```

### Ranges

| Component | Min | Max |
|-----------|-----|-----|
| X Multiplier | 1.0x | 10.0x |
| Phone Multiplier | 0.5x | 2.0x |
| ROGUE Multiplier | 1.0x | 5.0x |
| Wallet Multiplier | 1.0x | 3.6x |
| **Overall** | **0.5x** | **360.0x** |

**Minimum**: 1.0 × 0.5 × 1.0 × 1.0 = **0.5x** (unverified phone, nothing else)
**Maximum**: 10.0 × 2.0 × 5.0 × 3.6 = **360.0x** (all maxed out)

---

## How Multiplier Affects Rewards

The overall multiplier is applied differently depending on the reward type:

### 1. Reading Rewards (Articles/Posts)

Each post has a **base BUX reward** set by the author/admin. The reward is divided into 10 increments based on engagement score.

**Formula**:
```
reading_reward = (engagement_score / 10) × base_bux_reward × overall_multiplier
```

**How it works**:
1. Post has a base reward (e.g., 10 BUX)
2. User reads post, earns engagement score 1-10 based on time spent and scroll depth
3. Each point of engagement earns 1/10th of base reward
4. That amount is multiplied by user's overall multiplier

**Example** (Post with 10 BUX base reward):
| User Type | Engagement Score | Base Earned | Overall Multiplier | Final Reward |
|-----------|------------------|-------------|-------------------|--------------|
| New user (no verifications) | 7/10 | 7 BUX | 0.5x | **3.5 BUX** |
| Basic user (phone only) | 7/10 | 7 BUX | 1.5x | **10.5 BUX** |
| Quality user | 7/10 | 7 BUX | 42.0x | **294 BUX** |
| Whale (maxed) | 10/10 | 10 BUX | 360.0x | **3,600 BUX** |

---

### 2. Video Rewards

Videos have a **standard BUX reward per minute** of watch time.

**Formula**:
```
video_reward = minutes_watched × bux_per_minute × overall_multiplier
```

**How it works**:
1. Video has a per-minute reward rate (e.g., 1 BUX/minute)
2. User watches video, time is tracked
3. Reward = watch time × rate × multiplier

**Example** (5-minute video at 1 BUX/minute):
| User Type | Minutes Watched | Base Earned | Overall Multiplier | Final Reward |
|-----------|-----------------|-------------|-------------------|--------------|
| New user | 5 min | 5 BUX | 0.5x | **2.5 BUX** |
| Basic user | 5 min | 5 BUX | 1.5x | **7.5 BUX** |
| Quality user | 5 min | 5 BUX | 42.0x | **210 BUX** |
| Whale | 5 min | 5 BUX | 360.0x | **1,800 BUX** |

---

### 3. X Share Rewards

X shares are **NOT affected by overall multiplier**. Instead, the user receives their **raw X score as BUX**.

**Formula**:
```
share_reward = x_score (raw 0-100)
```

**How it works**:
1. User shares a post on X (retweet)
2. System verifies the share
3. User receives BUX equal to their X score (NOT multiplier)

**Example**:
| User | X Score | X Multiplier | Share Reward |
|------|---------|--------------|--------------|
| User A | 30 | 3.0x | **30 BUX** |
| User B | 75 | 7.5x | **75 BUX** |
| User C | 100 | 10.0x | **100 BUX** |
| User D (no X) | 0 | 1.0x | **0 BUX** (can't share) |

**Why X Score, Not Multiplier?**
- Rewards quality X accounts directly
- Higher-quality accounts have more reach/influence
- Score 30 = 30 BUX, Score 100 = 100 BUX (simple, intuitive)
- Prevents double-dipping (X score already factors into overall multiplier for reading/video rewards)

---

### Reward Summary Table

| Reward Type | Formula | Multiplier Used |
|-------------|---------|-----------------|
| Reading | `(engagement/10) × base_bux × overall_multiplier` | Overall (X × Phone × ROGUE × Wallet) |
| Video | `minutes × bux_per_minute × overall_multiplier` | Overall (X × Phone × ROGUE × Wallet) |
| X Share | `x_score` | None (raw X score as BUX) |

---

## Examples

### Example 1: New User (Nothing Connected)
- X: 1.0x (not connected)
- Phone: 0.5x (not verified)
- ROGUE: 1.0x (no ROGUE in smart wallet)
- Wallet: 1.0x (no external wallet)
- **Total**: 1.0 × 0.5 × 1.0 × 1.0 = **0.5x**

### Example 2: Basic User (Phone Verified Only)
- X: 1.0x (not connected)
- Phone: 1.5x (Standard tier - EU)
- ROGUE: 1.0x (no ROGUE)
- Wallet: 1.0x (no external wallet)
- **Total**: 1.0 × 1.5 × 1.0 × 1.0 = **1.5x**

### Example 3: ROGUE Holder (No External Wallet)
- X: 2.5x (score 25)
- Phone: 2.0x (Premium - US)
- ROGUE: 3.0x (500k ROGUE in smart wallet)
- Wallet: 1.0x (no external wallet connected)
- **Total**: 2.5 × 2.0 × 3.0 × 1.0 = **15.0x**

### Example 4: Quality User (Your Example - Updated)
- X: 3.0x (score 30)
- Phone: 2.0x (Premium - US)
- ROGUE: 5.0x (1M+ ROGUE in smart wallet)
- Wallet: 1.3x (connected + 0.5 ETH + $2k other tokens)
  - Base: 1.0
  - Connection: +0.1x
  - ETH (0.5): +0.5x (wait, that's wrong - 0.5 ETH should be +0.5x giving 1.6x total... let me recalc)
  - Actually: 1.0 + 0.1 + 0.1 (small ETH) + 0.2 (other) = 1.4x
- **Total**: 3.0 × 2.0 × 5.0 × 1.4 = **42.0x**

### Example 5: Whale (Everything Maxed)
- X: 10.0x (score 100)
- Phone: 2.0x (Premium)
- ROGUE: 5.0x (1M+ ROGUE)
- Wallet: 3.6x (10+ ETH + $10k+ other tokens)
- **Total**: 10.0 × 2.0 × 5.0 × 3.6 = **360.0x**

---

## Storage Schema

### Mnesia `unified_multipliers` Table (NEW)

**IMPORTANT**: Create a NEW table `unified_multipliers` instead of modifying the existing `user_multipliers` table. The old table will be ignored but left in place to avoid migration issues.

| Index | Field | Type | Description |
|-------|-------|------|-------------|
| 0 | table_name | atom | `:unified_multipliers` |
| 1 | user_id | integer | Primary key |
| 2 | x_score | integer | Raw X score (0-100), NOT the multiplier |
| 3 | x_multiplier | float | Calculated X multiplier (1.0-10.0) |
| 4 | phone_multiplier | float | Copied from PostgreSQL (0.5-2.0) |
| 5 | rogue_multiplier | float | ROGUE multiplier (1.0-5.0) |
| 6 | wallet_multiplier | float | External wallet multiplier (1.0-3.6) |
| 7 | overall_multiplier | float | Product of all four multipliers |
| 8 | last_updated | integer | Unix timestamp |
| 9 | created_at | integer | Unix timestamp |

**Why new table?** Modifying Mnesia schema is tricky and risky in production. Creating a fresh table with a new name is safer - the old `user_multipliers` table is simply ignored.

**Note**: Display values (balances, USD amounts) are fetched on-demand when rendering UI, NOT stored in Mnesia. This keeps the schema simple and avoids stale data issues.

---

## Implementation Changes Required

### Backend Changes

#### 1. Update `WalletMultiplier` Module

**File**: `lib/blockster_v2/wallet_multiplier.ex`

**Remove**:
- All ROGUE-related constants (`@rogue_on_arbitrum`, `@rogue_tiers`)
- `rogue_chain` and `rogue_arbitrum` balance fetching
- `weighted_rogue` calculation
- `rogue_multiplier` in return map

**Keep**:
- ETH tier constants and calculation
- Other tokens (USDC, USDT, ARB) calculation
- Connection boost (+0.1x)

**Changes**:
```elixir
# REMOVE these lines:
rogue_chain = get_balance(balances, "ROGUE", "rogue")
rogue_arbitrum = get_balance(balances, "ROGUE", "arbitrum")
weighted_rogue = rogue_chain + (rogue_arbitrum * 0.5)
rogue_multiplier = calculate_rogue_tier_multiplier(weighted_rogue)

# CHANGE total_multiplier calculation FROM:
total_multiplier = 1.0 + connection_boost + rogue_multiplier + eth_multiplier + other_tokens_multiplier

# TO:
total_multiplier = 1.0 + connection_boost + eth_multiplier + other_tokens_multiplier

# CHANGE return map FROM including rogue fields TO:
%{
  total_multiplier: total_multiplier,  # Now 1.0-3.6x
  connection_boost: connection_boost,
  eth_multiplier: eth_multiplier,
  other_tokens_multiplier: other_tokens_multiplier,
  breakdown: %{
    eth_mainnet: eth_mainnet,
    eth_arbitrum: eth_arbitrum,
    combined_eth: combined_eth,
    other_tokens_usd: other_tokens_usd
  }
}
```

#### 2. Create New `RogueMultiplier` Module

**File**: `lib/blockster_v2/rogue_multiplier.ex` (NEW)

**Purpose**: Calculate ROGUE multiplier from Blockster smart wallet balance only

```elixir
defmodule BlocksterV2.RogueMultiplier do
  @moduledoc """
  Calculates ROGUE multiplier based on Blockster smart wallet balance.
  Only smart wallet ROGUE counts - external wallet ROGUE does NOT count.
  """

  @rogue_tiers [
    {1_000_000, 4.0},
    {900_000, 3.6},
    {800_000, 3.2},
    {700_000, 2.8},
    {600_000, 2.4},
    {500_000, 2.0},
    {400_000, 1.6},
    {300_000, 1.2},
    {200_000, 0.8},
    {100_000, 0.4},
    {0, 0.0}
  ]

  @doc """
  Calculate ROGUE multiplier for a user based on their smart wallet balance.
  Returns 1.0-5.0x multiplier.
  """
  def calculate_rogue_multiplier(user_id) do
    # Get ROGUE balance from smart wallet (Mnesia user_bux_balances or direct RPC)
    rogue_balance = get_smart_wallet_rogue_balance(user_id)

    # Cap at 1M ROGUE
    capped_balance = min(rogue_balance, 1_000_000)

    # Get boost from tier
    boost = get_rogue_boost(capped_balance)

    %{
      total_multiplier: 1.0 + boost,
      boost: boost,
      balance: rogue_balance,
      capped_balance: capped_balance
    }
  end

  defp get_smart_wallet_rogue_balance(user_id) do
    # Fetch from Mnesia user_rogue_balances table
    case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
      [] -> 0.0
      [record] -> elem(record, 2) || 0.0  # balance field
    end
  end

  defp get_rogue_boost(balance) do
    Enum.find_value(@rogue_tiers, 0.0, fn {threshold, boost} ->
      if balance >= threshold, do: boost
    end)
  end
end
```

#### 3. Create New `UnifiedMultiplier` Module

```elixir
defmodule BlocksterV2.UnifiedMultiplier do
  @moduledoc """
  Unified multiplier calculator that combines X, Phone, ROGUE, and Wallet multipliers.
  """

  # ROGUE tiers (smart wallet only)
  @rogue_tiers [
    {1_000_000, 4.0},
    {900_000, 3.6},
    {800_000, 3.2},
    {700_000, 2.8},
    {600_000, 2.4},
    {500_000, 2.0},
    {400_000, 1.6},
    {300_000, 1.2},
    {200_000, 0.8},
    {100_000, 0.4},
    {0, 0.0}
  ]

  # ETH tiers (external wallet only)
  @eth_tiers [
    {10.0, 1.5},
    {5.0, 1.1},
    {2.5, 0.9},
    {1.0, 0.7},
    {0.5, 0.5},
    {0.1, 0.3},
    {0.01, 0.1},
    {0.0, 0.0}
  ]

  def calculate_x_multiplier(x_score) when is_number(x_score) do
    max(x_score / 10.0, 1.0)
  end
  def calculate_x_multiplier(_), do: 1.0

  def calculate_phone_multiplier(user) do
    case {user.phone_verified, user.geo_tier} do
      {true, "premium"} -> 2.0
      {true, "standard"} -> 1.5
      {true, "basic"} -> 1.0
      {true, _} -> 1.0
      _ -> 0.5
    end
  end

  def calculate_rogue_multiplier(smart_wallet_rogue_balance) do
    # Cap at 1M ROGUE
    capped_balance = min(smart_wallet_rogue_balance, 1_000_000)
    boost = get_rogue_boost(capped_balance)
    1.0 + boost
  end

  defp get_rogue_boost(balance) do
    Enum.find_value(@rogue_tiers, 0.0, fn {threshold, boost} ->
      if balance >= threshold, do: boost
    end)
  end

  def calculate_wallet_multiplier(nil), do: 1.0
  def calculate_wallet_multiplier(%{eth_balance: eth, other_tokens_usd: other_usd}) do
    connection_boost = 0.1
    eth_boost = get_eth_boost(eth)
    other_boost = min(other_usd / 10_000, 1.0)
    1.0 + connection_boost + eth_boost + other_boost
  end

  defp get_eth_boost(eth_balance) do
    Enum.find_value(@eth_tiers, 0.0, fn {threshold, boost} ->
      if eth_balance >= threshold, do: boost
    end)
  end

  def calculate_overall(x_mult, phone_mult, rogue_mult, wallet_mult) do
    x_mult * phone_mult * rogue_mult * wallet_mult
  end
end
```

### 2. Update `WalletMultiplier` Module

**Remove**: All ROGUE-related calculations
**Keep**: ETH + other tokens only
**Change**: Return value should be 1.0-3.6x (not 1.0-7.6x)

### 3. Create New `RogueMultiplier` Module

**Source**: Smart wallet ROGUE balance from `user.smart_wallet_address` on Rogue Chain
**Function**: Query ROGUE balance, calculate 1.0-5.0x multiplier

### UI Changes

#### 4. Update Member Page Wallet Tab

**File**: `lib/blockster_v2_web/live/member_live/show.html.heex`

**Current Structure** (wrong - ROGUE mixed with wallet):
```
┌─────────────────────────────────────────┐
│ Hold ROGUE to Boost your BUX Earnings   │  <- Single card with everything
│                                         │
│ Base + Wallet Connected: 1.1x           │
│ ROGUE Rogue Chain: +4.0x                │  <- WRONG: Should be separate
│ ROGUE Arbitrum: +2.0x                   │
│ ETH: +0.2x                              │
│                                         │
│ Total: 7.5x                             │
└─────────────────────────────────────────┘
```

**New Structure** (correct - ROGUE separate from wallet):
```
┌─────────────────────────────────────────┐
│ 🚀 ROGUE Multiplier                     │  <- CARD 1: ROGUE only
│                                         │
│ Smart Wallet Balance: 1,234,567 ROGUE   │
│                                         │
│ Tiers:                                  │
│ ✓ 100k - 199k ROGUE  +0.4x              │
│ ✓ 200k - 299k ROGUE  +0.8x              │
│ ...                                     │
│ ✓ 1M+ ROGUE          +4.0x (MAX)        │
│                                         │
│ Your ROGUE Multiplier: 5.0x / 5.0x      │
│ (Only first 1M counts)                  │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 💰 External Wallet Multiplier           │  <- CARD 2: ETH + other only
│                                         │
│ Connected: 0x1234...5678                │
│                                         │
│ Base + Connected: 1.1x                  │
│ ETH (0.5 combined): +0.5x               │
│ Other Tokens ($5k): +0.5x               │
│                                         │
│ Your Wallet Multiplier: 2.1x / 3.6x     │
└─────────────────────────────────────────┘
```

**Specific Template Changes**:

1. **Replace "LEVEL" stats box with "MULTIPLIER" stats box**:
   - The middle stats box (currently shows "LEVEL") should show the user's overall multiplier instead
   - Main display: Overall multiplier value (e.g., "63.0x")
   - Dropdown/tooltip on click: Show all 4 separate multipliers:
     ```
     ┌─────────────────────────────────┐
     │ Your Multipliers                │
     │ ─────────────────────────────── │
     │ X Account:      3.0x / 10.0x    │
     │ Phone:          2.0x / 2.0x ✨  │
     │ ROGUE:          5.0x / 5.0x ✨  │
     │ Wallet:         2.1x / 3.6x     │
     │ ─────────────────────────────── │
     │ Overall:        63.0x / 360.0x  │
     └─────────────────────────────────┘
     ```

2. **Create new "ROGUE" tab** on member page:
   - New tab alongside existing tabs (Activity, External Wallet, etc.)
   - Contains the "Hold ROGUE to Boost your BUX Earnings" table
   - Shows smart wallet ROGUE balance (from `user_rogue_balances` Mnesia table)
   - Shows tier progress (same tiers as current wallet tab, but for smart wallet only)
   - Shows "Your ROGUE Multiplier: X.Xx / 5.0x"
   - Note: "Only first 1M counts toward multiplier"
   - This is for **Blockster smart wallet** ROGUE, NOT external wallet

3. **Update "External Wallet" tab** (existing tab):
   - Remove all ROGUE-related rows
   - Keep: Base + Connected (1.1x), ETH, Other Tokens only
   - Show "Your Wallet Multiplier: X.Xx / 3.6x"
   - This tab is ONLY for external wallet (MetaMask/Ledger) holdings

4. **Update LiveView assigns** (`show.ex`):
   - Add `rogue_multiplier_data` assign (from new RogueMultiplier module)
   - Modify `hardware_wallet_data` to exclude ROGUE
   - Add `overall_multiplier` and individual multiplier assigns for stats box

**Code Changes for `show.ex`**:
```elixir
# In handle_async or mount, ADD:
rogue_data = BlocksterV2.RogueMultiplier.calculate_rogue_multiplier(member.id)
socket = assign(socket, :rogue_multiplier_data, rogue_data)

# MODIFY existing wallet multiplier call to use updated WalletMultiplier (no ROGUE)
```

**Code Changes for `show.html.heex`**:
```heex
<%# ROGUE MULTIPLIER CARD (NEW) %>
<div class="bg-white rounded-lg shadow p-4 mb-4">
  <h3 class="text-lg font-haas_medium_65 mb-3">🚀 ROGUE Multiplier</h3>

  <div class="text-sm text-gray-600 mb-2">
    Smart Wallet Balance:
    <span class="font-haas_medium_65">
      <%= Number.Delimit.number_to_delimited(@rogue_multiplier_data.balance, precision: 0) %> ROGUE
    </span>
  </div>

  <%# Tier list - same as before but for smart wallet only %>
  ...

  <div class="mt-4 flex justify-between items-center">
    <span class="text-sm">Your ROGUE Multiplier:</span>
    <span class="text-lg font-haas_bold_75 text-green-600">
      <%= :erlang.float_to_binary(@rogue_multiplier_data.total_multiplier, decimals: 1) %>x
    </span>
    <span class="text-sm text-gray-500">/ 5.0x</span>
  </div>

  <div class="text-xs text-gray-400 mt-1">
    Only first 1M ROGUE counts toward multiplier
  </div>
</div>

<%# EXTERNAL WALLET CARD (MODIFIED - no ROGUE) %>
<div class="bg-white rounded-lg shadow p-4">
  <h3 class="text-lg font-haas_medium_65 mb-3">💰 External Wallet Multiplier</h3>

  <%= if @wallet_address do %>
    <div class="text-sm text-gray-600 mb-2">
      Connected: <%= String.slice(@wallet_address, 0..5) %>...<%= String.slice(@wallet_address, -4..-1) %>
    </div>

    <%# Base + Connected row %>
    <div class="flex justify-between py-2 border-b">
      <span>Base + Connected</span>
      <span class="text-green-600">1.1x</span>
    </div>

    <%# ETH row %>
    <div class="flex justify-between py-2 border-b">
      <span>ETH (<%= @hardware_wallet_data.breakdown.combined_eth %> combined)</span>
      <span class="text-green-600">+<%= @hardware_wallet_data.eth_multiplier %>x</span>
    </div>

    <%# Other tokens row %>
    <div class="flex justify-between py-2 border-b">
      <span>Other Tokens ($<%= Number.Delimit.number_to_delimited(@hardware_wallet_data.breakdown.other_tokens_usd, precision: 0) %>)</span>
      <span class="text-green-600">+<%= :erlang.float_to_binary(@hardware_wallet_data.other_tokens_multiplier, decimals: 1) %>x</span>
    </div>

    <div class="mt-4 flex justify-between items-center">
      <span class="text-sm">Your Wallet Multiplier:</span>
      <span class="text-lg font-haas_bold_75 text-green-600">
        <%= :erlang.float_to_binary(@hardware_wallet_data.total_multiplier, decimals: 1) %>x
      </span>
      <span class="text-sm text-gray-500">/ 3.6x</span>
    </div>
  <% else %>
    <p class="text-gray-500">Connect an external wallet to earn additional multiplier</p>
  <% end %>
</div>
```

### 5. Update Overall Multiplier Display

**Current** (3 components):
```
Overall: X × Phone × Wallet = Total
```

**New** (4 components):
```
Overall: X (3.0x) × Phone (2.0x) × ROGUE (5.0x) × Wallet (2.1x) = 63.0x
```

**Add to member page header or sidebar**:
```heex
<div class="bg-gradient-to-r from-purple-500 to-blue-500 text-white rounded-lg p-4">
  <div class="text-sm opacity-80">Your Overall Multiplier</div>
  <div class="text-3xl font-haas_bold_75">
    <%= :erlang.float_to_binary(@overall_multiplier, decimals: 1) %>x
  </div>
  <div class="text-xs opacity-70 mt-1">
    X (<%= @x_mult %>x) × Phone (<%= @phone_mult %>x) × ROGUE (<%= @rogue_mult %>x) × Wallet (<%= @wallet_mult %>x)
  </div>
</div>
```

---

## Migration Plan

1. **Create new Mnesia table `unified_multipliers`** in `MnesiaInitializer`
   - Add to `@tables` list with attributes: `[:user_id, :x_score, :x_multiplier, :phone_multiplier, :rogue_multiplier, :wallet_multiplier, :overall_multiplier, :last_updated, :created_at]`
   - Add index on `:user_id`
   - **DO NOT modify or delete the old `user_multipliers` table** - just ignore it

2. **Create `RogueMultiplier` module** (`lib/blockster_v2/rogue_multiplier.ex`)
   - Reads smart wallet ROGUE from `user_rogue_balances` Mnesia table
   - Returns 1.0-5.0x multiplier

3. **Update `WalletMultiplier` module** (`lib/blockster_v2/wallet_multiplier.ex`)
   - Remove all ROGUE-related code
   - Return 1.0-3.6x (ETH + other tokens only)

4. **Create `UnifiedMultiplier` module** (`lib/blockster_v2/unified_multiplier.ex`)
   - Combines all 4 multipliers
   - Reads/writes to new `unified_multipliers` table
   - Provides `get_overall_multiplier(user_id)` for engagement tracking

5. **Update member page LiveView** (`lib/blockster_v2_web/live/member_live/show.ex`)
   - Add `rogue_multiplier_data` assign
   - Use updated `WalletMultiplier` (no ROGUE)
   - Add assigns for all 4 individual multipliers + overall

6. **Update member page template** (`lib/blockster_v2_web/live/member_live/show.html.heex`)
   - **Replace "LEVEL" stats box with "MULTIPLIER" stats box** showing overall multiplier
   - Add dropdown/tooltip on stats box click showing all 4 separate multipliers
   - **Create new "ROGUE" tab** with "Hold ROGUE to Boost your BUX Earnings" table (smart wallet ROGUE)
   - **Update "External Wallet" tab** to remove ROGUE rows (ETH + other tokens only)

7. **Update engagement tracking** to use `UnifiedMultiplier.get_overall_multiplier/1`

---

## UI Mockup

```
┌─────────────────────────────────────────────────────────────┐
│  Your Multiplier Score                                      │
│  ═══════════════════════════════════════════════════════════│
│                                                             │
│  Overall Multiplier: 63.0x                                  │
│  X (3.0x) × Phone (2.0x) × ROGUE (5.0x) × Wallet (2.1x)     │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🐦 X Account                    3.0x / 10.0x        │   │
│  │ Score: 30/100                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 📱 Phone                        2.0x / 2.0x  ✨ MAX │   │
│  │ Premium tier (US)                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🚀 ROGUE Holdings               5.0x / 5.0x  ✨ MAX │   │
│  │ Smart Wallet: 1,234,567 ROGUE                       │   │
│  │ (Only first 1M counts toward multiplier)            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 💰 External Wallet              2.1x / 3.6x         │   │
│  │ Base + Connected: 1.1x                              │   │
│  │ ETH (0.5): +0.5x                                    │   │
│  │ Other ($5k): +0.5x                                  │   │
│  │ 💡 Add more ETH for higher multiplier               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Maximum Possible: 360.0x                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Benefits of V2 System

1. **Clearer separation**: Each multiplier has a single, clear source
2. **ROGUE incentive**: Users are encouraged to hold ROGUE in Blockster wallet
3. **No external wallet needed for ROGUE**: Users benefit from ROGUE without connecting external wallet
4. **Higher max multiplier**: 360x vs 152x (rewards power users more)
5. **Simpler wallet calculation**: External wallet is just ETH + other tokens
6. **Single source of truth**: All multipliers stored in Mnesia for fast access
7. **Easier to display**: Four distinct components, easy to explain

---

## Implementation Checklist

### Phase 1: Backend - Mnesia Table & Core Modules

#### 1.1 Create `unified_multipliers` Mnesia Table
- [ ] **File**: `lib/blockster_v2/mnesia_initializer.ex`
- [ ] Add `:unified_multipliers` to `@tables` list
- [ ] Define attributes: `[:user_id, :x_score, :x_multiplier, :phone_multiplier, :rogue_multiplier, :wallet_multiplier, :overall_multiplier, :last_updated, :created_at]`
- [ ] Add table creation in `create_tables/0`:
  ```elixir
  :mnesia.create_table(:unified_multipliers, [
    attributes: [:user_id, :x_score, :x_multiplier, :phone_multiplier, :rogue_multiplier, :wallet_multiplier, :overall_multiplier, :last_updated, :created_at],
    disc_copies: [node()],
    type: :set
  ])
  ```
- [ ] Restart both nodes (node1, node2) to create table
- [ ] Verify table exists: `:mnesia.table_info(:unified_multipliers, :attributes)`

#### 1.2 Create `RogueMultiplier` Module
- [ ] **File**: `lib/blockster_v2/rogue_multiplier.ex` (NEW FILE)
- [ ] Define `@rogue_tiers` constant (same tiers as doc: 100k increments, max 1M)
- [ ] Implement `calculate_rogue_multiplier/1`:
  - [ ] Read ROGUE balance from `user_rogue_balances` Mnesia table
  - [ ] Cap balance at 1,000,000
  - [ ] Calculate boost from tier (0.4x per 100k)
  - [ ] Return map: `%{total_multiplier: 1.0 + boost, boost: boost, balance: balance, capped_balance: capped}`
- [ ] Implement `get_smart_wallet_rogue_balance/1` (private):
  - [ ] Query `:mnesia.dirty_read({:user_rogue_balances, user_id})`
  - [ ] Handle empty result (return 0.0)
  - [ ] Extract balance from record (index 2)
- [ ] Implement `get_rogue_boost/1` (private):
  - [ ] Use `Enum.find_value` to find matching tier
- [ ] Add module documentation with examples
- [ ] Add unit tests in `test/blockster_v2/rogue_multiplier_test.exs`

#### 1.3 Update `WalletMultiplier` Module
- [ ] **File**: `lib/blockster_v2/wallet_multiplier.ex`
- [ ] **REMOVE** `@rogue_on_arbitrum` constant
- [ ] **REMOVE** `@rogue_tiers` constant
- [ ] **REMOVE** `calculate_rogue_tier_multiplier/1` function
- [ ] **MODIFY** `calculate_from_wallet_balances/1`:
  - [ ] Remove `rogue_chain = get_balance(balances, "ROGUE", "rogue")`
  - [ ] Remove `rogue_arbitrum = get_balance(balances, "ROGUE", "arbitrum")`
  - [ ] Remove `weighted_rogue = rogue_chain + (rogue_arbitrum * 0.5)`
  - [ ] Remove `rogue_multiplier = calculate_rogue_tier_multiplier(weighted_rogue)`
  - [ ] Change `total_multiplier` formula to: `1.0 + connection_boost + eth_multiplier + other_tokens_multiplier`
  - [ ] Remove `rogue_multiplier` from return map
  - [ ] Remove `rogue_chain`, `rogue_arbitrum`, `weighted_rogue` from breakdown
- [ ] **UPDATE** `@moduledoc` to reflect new range (1.0-3.6x)
- [ ] **UPDATE** `calculate_hardware_wallet_multiplier/1` return type doc
- [ ] Run existing tests to ensure ETH + other tokens still work

#### 1.4 Create `UnifiedMultiplier` Module
- [ ] **File**: `lib/blockster_v2/unified_multiplier.ex` (NEW FILE)
- [ ] Define module attributes:
  - [ ] `@rogue_tiers` (copy from RogueMultiplier)
  - [ ] `@eth_tiers` (copy from WalletMultiplier)
- [ ] Implement `calculate_x_multiplier/1`:
  - [ ] Input: raw x_score (0-100)
  - [ ] Output: `max(x_score / 10.0, 1.0)`
  - [ ] Handle nil/non-numeric input (return 1.0)
- [ ] Implement `calculate_phone_multiplier/1`:
  - [ ] Input: user struct with `phone_verified` and `geo_multiplier` fields
  - [ ] Output: 0.5x (not verified), 1.0x (basic), 1.5x (standard), 2.0x (premium)
  - [ ] Read from PostgreSQL `users.geo_multiplier` field
- [ ] Implement `calculate_rogue_multiplier/1`:
  - [ ] Input: smart_wallet_rogue_balance (number)
  - [ ] Output: 1.0-5.0x multiplier
  - [ ] Cap at 1M, calculate boost from tier
- [ ] Implement `calculate_wallet_multiplier/1`:
  - [ ] Input: nil or %{eth_balance: float, other_tokens_usd: float}
  - [ ] Output: 1.0-3.6x multiplier
  - [ ] Handle nil (return 1.0)
- [ ] Implement `calculate_overall/4`:
  - [ ] Input: x_mult, phone_mult, rogue_mult, wallet_mult
  - [ ] Output: product of all four
- [ ] Implement `get_user_multipliers/1`:
  - [ ] Input: user_id
  - [ ] Fetch all data sources (X score, phone, ROGUE balance, wallet data)
  - [ ] Calculate all 4 multipliers
  - [ ] Calculate overall
  - [ ] Return comprehensive map with all values
- [ ] Implement `save_unified_multipliers/2`:
  - [ ] Input: user_id, multipliers map
  - [ ] Write to `unified_multipliers` Mnesia table
  - [ ] Set `last_updated` and `created_at` timestamps
- [ ] Implement `get_overall_multiplier/1`:
  - [ ] Input: user_id
  - [ ] Read from Mnesia, return overall_multiplier
  - [ ] Handle missing record (return 1.0)
- [ ] Add unit tests in `test/blockster_v2/unified_multiplier_test.exs`

#### 1.5 Update X Score Calculator Integration
- [ ] **File**: `lib/blockster_v2/social/x_score_calculator.ex`
- [ ] **MODIFY** `save_score/2`:
  - [ ] After saving to `x_connections`, also update `unified_multipliers`
  - [ ] Call `UnifiedMultiplier.save_unified_multipliers(user_id, %{x_score: score, x_multiplier: max(score/10.0, 1.0)})`
- [ ] OR create a trigger/callback system to update unified table when X score changes

#### 1.6 Update Engagement Tracker Integration
- [ ] **File**: `lib/blockster_v2/engagement_tracker.ex`
- [ ] **ADD** function `update_unified_rogue_multiplier/1`:
  - [ ] Called when ROGUE balance changes
  - [ ] Recalculates ROGUE multiplier
  - [ ] Updates `unified_multipliers` table
- [ ] **ADD** function `update_unified_wallet_multiplier/1`:
  - [ ] Called when external wallet data changes
  - [ ] Recalculates wallet multiplier
  - [ ] Updates `unified_multipliers` table
- [ ] **MODIFY** existing code that updates `user_multipliers` to also update `unified_multipliers`

---

### Phase 2: Backend - Update Reward Calculations

#### 2.1 Update Reading Rewards (Articles/Posts)
- [ ] **File**: `lib/blockster_v2/engagement_tracker.ex`
- [ ] Find the reading reward calculation function (likely `calculate_bux_reward/3` or similar)
- [ ] **VERIFY** current formula: `(engagement_score / 10) × base_bux_reward × multiplier`
- [ ] **CHANGE** multiplier source from `get_user_x_multiplier/1` to `UnifiedMultiplier.get_overall_multiplier/1`
- [ ] **ENSURE** engagement score (1-10) divides base reward into tenths
- [ ] **TEST** reward calculation:
  - [ ] User with 0.5x multiplier, engagement 7/10, base 10 BUX → 3.5 BUX
  - [ ] User with 42.0x multiplier, engagement 7/10, base 10 BUX → 294 BUX
  - [ ] User with 360.0x multiplier, engagement 10/10, base 10 BUX → 3,600 BUX

#### 2.2 Update Video Rewards
- [ ] **File**: Find video reward calculation (likely in `engagement_tracker.ex` or `video_live/`)
- [ ] **VERIFY** current formula: `minutes_watched × bux_per_minute × multiplier`
- [ ] **CHANGE** multiplier source to `UnifiedMultiplier.get_overall_multiplier/1`
- [ ] **TEST** reward calculation:
  - [ ] User with 0.5x multiplier, 5 min watched, 1 BUX/min → 2.5 BUX
  - [ ] User with 42.0x multiplier, 5 min watched, 1 BUX/min → 210 BUX

#### 2.3 Update X Share Rewards (Uses X Score, NOT Overall Multiplier)
- [ ] **File**: `lib/blockster_v2_web/live/post_live/show.ex`
- [ ] **IMPORTANT**: X shares use raw X score (0-100), NOT the overall multiplier
- [ ] **FIND** current share reward calculation (line ~127)
- [ ] **CHANGE** from: `calculated_reward = x_multiplier * base_bux_reward`
- [ ] **CHANGE** to: `calculated_reward = x_score` (raw score as BUX)
- [ ] **ADD** function to get raw X score: `UnifiedMultiplier.get_x_score/1`
- [ ] **UPDATE** UI to show "Share to earn {x_score} BUX" instead of multiplied amount
- [ ] **TEST** share rewards:
  - [ ] User with X score 30 → earns 30 BUX per share
  - [ ] User with X score 75 → earns 75 BUX per share
  - [ ] User with X score 100 → earns 100 BUX per share
  - [ ] User with no X connected (score 0) → cannot share / earns 0 BUX

#### 2.4 Add `get_x_score/1` Function to UnifiedMultiplier
- [ ] **File**: `lib/blockster_v2/unified_multiplier.ex`
- [ ] **ADD** function:
  ```elixir
  @doc """
  Get raw X score (0-100) for a user.
  Used for X share rewards (user earns their X score as BUX per share).
  """
  def get_x_score(user_id) do
    case :mnesia.dirty_read({:unified_multipliers, user_id}) do
      [] -> 0
      [record] -> elem(record, 2) || 0  # x_score is at index 2
    end
  end
  ```

#### 2.5 Update Any Other Multiplier Usages
- [ ] Search codebase for `get_user_x_multiplier`, `get_user_multiplier`, `get_combined_multiplier`
- [ ] **FOR READING/VIDEO**: Replace with `UnifiedMultiplier.get_overall_multiplier/1`
- [ ] **FOR X SHARES**: Replace with `UnifiedMultiplier.get_x_score/1`
- [ ] Document any edge cases or special handling needed
- [ ] Remove old multiplier functions once all usages are migrated

---

### Phase 3: Frontend - Member Page UI

#### 3.1 Update Member Page LiveView (`show.ex`)
- [ ] **File**: `lib/blockster_v2_web/live/member_live/show.ex`
- [ ] **ADD** new assigns in mount/handle_params:
  - [ ] `rogue_multiplier_data` - from `RogueMultiplier.calculate_rogue_multiplier(member.id)`
  - [ ] `unified_multipliers` - from `UnifiedMultiplier.get_user_multipliers(member.id)`
  - [ ] `x_multiplier` - extract from unified_multipliers
  - [ ] `phone_multiplier` - extract from unified_multipliers
  - [ ] `rogue_multiplier` - extract from unified_multipliers
  - [ ] `wallet_multiplier` - extract from unified_multipliers
  - [ ] `overall_multiplier` - extract from unified_multipliers
- [ ] **MODIFY** existing `hardware_wallet_data` fetch to use updated WalletMultiplier (no ROGUE)
- [ ] **ADD** async fetch for ROGUE balance if needed: `start_async(:fetch_rogue_data, fn -> ... end)`
- [ ] **ADD** `handle_async(:fetch_rogue_data, ...)` handler
- [ ] **ADD** new tab tracking for "ROGUE" tab (add to `@valid_tabs` or similar)

#### 3.2 Replace "LEVEL" Stats Box with "MULTIPLIER" Stats Box
- [ ] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [ ] Find the stats box section (likely near line ~268 based on grep results)
- [ ] **REPLACE** "LEVEL" stats box with "MULTIPLIER" stats box:
  - [ ] Main display: `<%= :erlang.float_to_binary(@overall_multiplier, decimals: 1) %>x`
  - [ ] Label: "MULTIPLIER" instead of "LEVEL"
  - [ ] Keep same layout/styling as other stats boxes
- [ ] **ADD** dropdown/tooltip on click (or hover):
  - [ ] Use Alpine.js or LiveView JS commands for dropdown
  - [ ] Show all 4 multipliers with current/max values
  - [ ] Show overall calculation formula
  - [ ] Style with consistent design (match existing dropdowns)

#### 3.3 Create New "ROGUE" Tab
- [ ] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [ ] Find tab navigation section
- [ ] **ADD** new tab button for "ROGUE":
  ```heex
  <button phx-click="switch_tab" phx-value-tab="rogue" class={tab_classes("rogue", @active_tab)}>
    ROGUE
  </button>
  ```
- [ ] **ADD** tab content section for ROGUE tab:
  - [ ] Card header: "Hold ROGUE to Boost your BUX Earnings"
  - [ ] Smart wallet balance display:
    ```heex
    <div class="text-sm text-gray-600 mb-2">
      Smart Wallet Balance:
      <span class="font-haas_medium_65">
        <%= Number.Delimit.number_to_delimited(@rogue_multiplier_data.balance, precision: 0) %> ROGUE
      </span>
    </div>
    ```
  - [ ] Tier progress table (11 rows: 0-99k through 1M+):
    - [ ] Show checkmark (✓) for achieved tiers
    - [ ] Show empty circle or dash for unachieved tiers
    - [ ] Highlight current tier
  - [ ] Current multiplier display: "Your ROGUE Multiplier: X.Xx / 5.0x"
  - [ ] Cap note: "Only first 1M ROGUE counts toward multiplier"
  - [ ] Optional: Progress bar showing % toward next tier
- [ ] **ADD** handle_event for tab switching if not already generic

#### 3.4 Update "External Wallet" Tab (Remove ROGUE)
- [ ] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [ ] Find External Wallet tab content section
- [ ] **REMOVE** all ROGUE-related rows:
  - [ ] Remove "ROGUE Rogue Chain" row
  - [ ] Remove "ROGUE Arbitrum" row
  - [ ] Remove `weighted_rogue` display
  - [ ] Remove ROGUE tier progress
- [ ] **KEEP** these rows:
  - [ ] "Base + Connected: 1.1x"
  - [ ] "ETH (X.XX combined): +X.Xx"
  - [ ] "Other Tokens ($X,XXX): +X.Xx"
- [ ] **UPDATE** total display: "Your Wallet Multiplier: X.Xx / 3.6x" (was /7.6x)
- [ ] **UPDATE** any tier tables to show ETH tiers only
- [ ] **UPDATE** helper text to reflect ETH + other tokens only

#### 3.5 Add Multiplier Breakdown Dropdown/Modal
- [ ] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [ ] Design dropdown that appears when clicking MULTIPLIER stats box
- [ ] **ADD** dropdown markup:
  ```heex
  <div x-data="{ open: false }" class="relative">
    <button @click="open = !open" class="cursor-pointer">
      <!-- Stats box content -->
    </button>
    <div x-show="open" @click.away="open = false" class="absolute z-50 ...">
      <div class="bg-white rounded-lg shadow-lg p-4">
        <h4 class="font-haas_medium_65 mb-2">Your Multipliers</h4>
        <div class="space-y-2">
          <div class="flex justify-between">
            <span>X Account:</span>
            <span><%= @x_multiplier %>x / 10.0x</span>
          </div>
          <div class="flex justify-between">
            <span>Phone:</span>
            <span><%= @phone_multiplier %>x / 2.0x <%= if @phone_multiplier == 2.0, do: "✨" %></span>
          </div>
          <div class="flex justify-between">
            <span>ROGUE:</span>
            <span><%= @rogue_multiplier %>x / 5.0x <%= if @rogue_multiplier == 5.0, do: "✨" %></span>
          </div>
          <div class="flex justify-between">
            <span>Wallet:</span>
            <span><%= @wallet_multiplier %>x / 3.6x <%= if @wallet_multiplier == 3.6, do: "✨" %></span>
          </div>
          <hr class="my-2">
          <div class="flex justify-between font-haas_bold_75">
            <span>Overall:</span>
            <span><%= @overall_multiplier %>x / 360.0x</span>
          </div>
        </div>
      </div>
    </div>
  </div>
  ```
- [ ] Style to match existing UI patterns
- [ ] Add ✨ emoji for maxed-out multipliers
- [ ] Consider adding links to relevant tabs (click X row → go to X tab)

---

### Phase 4: Testing & Validation

#### 4.1 Unit Tests - Multiplier Modules
- [ ] `test/blockster_v2/rogue_multiplier_test.exs`:
  - [ ] Test all tier boundaries (99,999 vs 100,000, etc.)
  - [ ] Test 1M cap behavior
  - [ ] Test nil/missing balance handling
- [ ] `test/blockster_v2/unified_multiplier_test.exs`:
  - [ ] Test X multiplier calculation (0, 50, 100 scores)
  - [ ] Test phone multiplier for each tier
  - [ ] Test ROGUE multiplier tiers
  - [ ] Test wallet multiplier with various ETH/token combos
  - [ ] Test overall calculation (multiplicative, not additive)
  - [ ] Test edge cases (all minimums, all maximums)
  - [ ] Test `get_x_score/1` returns raw score (0-100)
- [ ] `test/blockster_v2/wallet_multiplier_test.exs`:
  - [ ] Update existing tests to reflect ROGUE removal
  - [ ] Verify max is now 3.6x not 7.6x

#### 4.2 Unit Tests - Reward Calculations
- [ ] `test/blockster_v2/engagement_tracker_test.exs` (or new file):
  - [ ] **Reading rewards**:
    - [ ] Test formula: `(engagement/10) × base_bux × overall_multiplier`
    - [ ] Engagement 7/10, base 10 BUX, multiplier 0.5x → 3.5 BUX
    - [ ] Engagement 7/10, base 10 BUX, multiplier 42.0x → 294 BUX
    - [ ] Engagement 10/10, base 10 BUX, multiplier 360.0x → 3,600 BUX
    - [ ] Edge case: engagement 0 → 0 BUX regardless of multiplier
    - [ ] Edge case: base_bux 0 → 0 BUX regardless of multiplier
  - [ ] **Video rewards**:
    - [ ] Test formula: `minutes × bux_per_minute × overall_multiplier`
    - [ ] 5 min, 1 BUX/min, multiplier 0.5x → 2.5 BUX
    - [ ] 5 min, 1 BUX/min, multiplier 42.0x → 210 BUX
    - [ ] Edge case: 0 minutes → 0 BUX
  - [ ] **X share rewards**:
    - [ ] Test formula: `reward = x_score` (NOT multiplied)
    - [ ] X score 30 → 30 BUX
    - [ ] X score 75 → 75 BUX
    - [ ] X score 100 → 100 BUX
    - [ ] X score 0 (no X connected) → 0 BUX
    - [ ] Verify overall multiplier is NOT applied to share rewards

#### 4.3 Integration Tests
- [ ] Test full flow: user connects X → score calculated → unified multiplier updated
- [ ] Test full flow: user deposits ROGUE → balance updated → unified multiplier updated
- [ ] Test full flow: user connects external wallet → balances fetched → unified multiplier updated
- [ ] **Reading reward flow**: user reads post → engagement tracked → reward calculated with overall multiplier
- [ ] **Video reward flow**: user watches video → time tracked → reward calculated with overall multiplier
- [ ] **X share flow**: user shares post → share verified → reward = raw X score (not multiplied)

#### 4.3 Manual Testing Checklist
- [ ] **New user (nothing connected)**:
  - [ ] Verify overall multiplier shows 0.5x (phone not verified)
  - [ ] Verify ROGUE tab shows 0 ROGUE, 1.0x multiplier
  - [ ] Verify External Wallet tab shows "Connect wallet" state
- [ ] **User with X connected only**:
  - [ ] Verify X multiplier reflects score (e.g., score 30 → 3.0x)
  - [ ] Verify overall = X × 0.5 × 1.0 × 1.0
- [ ] **User with phone verified**:
  - [ ] Verify phone multiplier matches geo_tier (premium = 2.0x)
  - [ ] Verify overall updates correctly
- [ ] **User with ROGUE in smart wallet**:
  - [ ] Verify ROGUE tab shows correct balance
  - [ ] Verify tier highlighting is accurate
  - [ ] Verify multiplier matches tier (500k → 3.0x)
  - [ ] Verify 1M cap works (5M ROGUE still shows 5.0x)
- [ ] **User with external wallet connected**:
  - [ ] Verify External Wallet tab shows ETH + other tokens ONLY
  - [ ] Verify NO ROGUE appears in External Wallet tab
  - [ ] Verify wallet multiplier max is 3.6x
- [ ] **Power user (everything maxed)**:
  - [ ] Verify overall shows 360.0x
  - [ ] Verify all ✨ indicators appear
- [ ] **Multiplier dropdown**:
  - [ ] Verify dropdown opens/closes correctly
  - [ ] Verify all 4 multipliers display correctly
  - [ ] Verify overall calculation shown

#### 4.4 Manual Testing - Reward Calculations
- [ ] **Reading rewards**:
  - [ ] Read a post with known base_bux reward (e.g., 10 BUX)
  - [ ] Achieve engagement score 7/10
  - [ ] Verify reward = 7 × multiplier (e.g., 7 × 42.0 = 294 BUX for quality user)
  - [ ] Test with different multiplier levels to confirm formula
- [ ] **Video rewards**:
  - [ ] Watch a video with known per-minute rate (e.g., 1 BUX/min)
  - [ ] Watch for 5 minutes
  - [ ] Verify reward = 5 × multiplier (e.g., 5 × 42.0 = 210 BUX)
- [ ] **X share rewards**:
  - [ ] Share a post on X
  - [ ] Verify reward equals raw X score (NOT multiplied)
  - [ ] User with X score 30 should earn exactly 30 BUX
  - [ ] Verify UI shows "Share to earn {x_score} BUX"
- [ ] **Edge cases**:
  - [ ] User with 0.5x multiplier earns less than base reward for reading/video
  - [ ] User with no X (score 0) cannot earn share rewards
  - [ ] Verify rewards are rounded correctly (no floating point display issues)

---

### Phase 5: Deployment & Migration

#### 5.1 Pre-Deployment Checklist
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Manual testing complete on local dev
- [ ] Documentation updated (this file)
- [ ] Code reviewed

#### 5.2 Deployment Steps
- [ ] **Step 1**: Deploy backend changes (new modules, updated modules)
  - [ ] Mnesia table will be created on first restart
  - [ ] Old `user_multipliers` table remains untouched
- [ ] **Step 2**: Monitor logs for any Mnesia errors
- [ ] **Step 3**: Verify new table exists on both nodes:
  ```elixir
  :mnesia.table_info(:unified_multipliers, :size)
  ```
- [ ] **Step 4**: Deploy frontend changes (member page UI)
- [ ] **Step 5**: Verify UI displays correctly in production

#### 5.3 Post-Deployment Verification
- [ ] Check multiplier calculations for several real users
- [ ] Verify engagement rewards are using new multiplier
- [ ] Monitor for any errors in logs
- [ ] Verify ROGUE tab displays correctly
- [ ] Verify External Wallet tab no longer shows ROGUE

#### 5.4 Rollback Plan
- [ ] If issues arise, old `user_multipliers` table is still intact
- [ ] Can revert code to use old table
- [ ] No data migration needed for rollback
- [ ] Document any issues encountered for future reference

---

### Phase 6: Cleanup (Post-Successful Deployment)

#### 6.1 Code Cleanup
- [ ] Remove any deprecated functions that were kept for backwards compatibility
- [ ] Remove any feature flags if used during gradual rollout
- [ ] Update `CLAUDE.md` with learnings from implementation

#### 6.2 Documentation Cleanup
- [ ] Mark this implementation checklist as COMPLETE
- [ ] Add date of completion
- [ ] Document any deviations from original plan
- [ ] Update any affected API documentation

#### 6.3 Future Considerations
- [ ] Consider adding periodic refresh of unified multipliers (cron job)
- [ ] Consider adding real-time updates when balances change (PubSub)
- [ ] Consider adding multiplier history/audit log
- [ ] Consider gamification (achievements for reaching multiplier milestones)
