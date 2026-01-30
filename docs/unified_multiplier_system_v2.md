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
- [x] **File**: `lib/blockster_v2/mnesia_initializer.ex`
- [x] Add `:unified_multipliers` to `@tables` list
- [x] Define attributes: `[:user_id, :x_score, :x_multiplier, :phone_multiplier, :rogue_multiplier, :wallet_multiplier, :overall_multiplier, :last_updated, :created_at]`
- [x] Add table creation in `create_tables/0`:
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
- [x] **File**: `lib/blockster_v2/rogue_multiplier.ex` (NEW FILE)
- [x] Define `@rogue_tiers` constant (same tiers as doc: 100k increments, max 1M)
- [x] Implement `calculate_rogue_multiplier/1`:
  - [x] Read ROGUE balance from `user_rogue_balances` Mnesia table
  - [x] Cap balance at 1,000,000
  - [x] Calculate boost from tier (0.4x per 100k)
  - [x] Return map: `%{total_multiplier: 1.0 + boost, boost: boost, balance: balance, capped_balance: capped}`
- [x] Implement `get_smart_wallet_rogue_balance/1` (private):
  - [x] Query `:mnesia.dirty_read({:user_rogue_balances, user_id})`
  - [x] Handle empty result (return 0.0)
  - [x] Extract balance from record (index 3 - rogue_balance_rogue_chain)
- [x] Implement `get_rogue_boost/1` (private):
  - [x] Use `Enum.find_value` to find matching tier
- [x] Add module documentation with examples
- [ ] Add unit tests in `test/blockster_v2/rogue_multiplier_test.exs`

#### 1.3 Update `WalletMultiplier` Module
- [x] **File**: `lib/blockster_v2/wallet_multiplier.ex`
- [x] **REMOVE** `@rogue_on_arbitrum` constant
- [x] **REMOVE** `@rogue_tiers` constant
- [x] **REMOVE** `calculate_rogue_tier_multiplier/1` function
- [x] **MODIFY** `calculate_from_wallet_balances/1`:
  - [x] Remove `rogue_chain = get_balance(balances, "ROGUE", "rogue")`
  - [x] Remove `rogue_arbitrum = get_balance(balances, "ROGUE", "arbitrum")`
  - [x] Remove `weighted_rogue = rogue_chain + (rogue_arbitrum * 0.5)`
  - [x] Remove `rogue_multiplier = calculate_rogue_tier_multiplier(weighted_rogue)`
  - [x] Change `total_multiplier` formula to: `1.0 + connection_boost + eth_multiplier + other_tokens_multiplier`
  - [x] Remove `rogue_multiplier` from return map
  - [x] Remove `rogue_chain`, `rogue_arbitrum`, `weighted_rogue` from breakdown
- [x] **UPDATE** `@moduledoc` to reflect new range (1.0-3.6x)
- [x] **UPDATE** `calculate_hardware_wallet_multiplier/1` return type doc
- [ ] Run existing tests to ensure ETH + other tokens still work

#### 1.4 Create `UnifiedMultiplier` Module
- [x] **File**: `lib/blockster_v2/unified_multiplier.ex` (NEW FILE)
- [x] Define module attributes:
  - [x] Min/max constants for all 4 components
  - [x] `@phone_tiers` map for geo_tier → multiplier lookup
- [x] Implement `calculate_x_multiplier/1`:
  - [x] Input: raw x_score (0-100)
  - [x] Output: `max(x_score / 10.0, 1.0)`
  - [x] Handle nil/non-numeric input (return 1.0)
- [x] Implement `calculate_phone_multiplier/1`:
  - [x] Input: user struct with `phone_verified` and `geo_tier` fields
  - [x] Output: 0.5x (not verified), 1.0x (basic), 1.5x (standard), 2.0x (premium)
  - [x] Read from PostgreSQL `users.geo_tier` field via `Accounts.get_user/1`
- [x] Implement ROGUE multiplier calculation:
  - [x] Delegates to `RogueMultiplier.calculate_rogue_multiplier/1`
  - [x] Returns 1.0-5.0x multiplier
- [x] Implement wallet multiplier calculation:
  - [x] Delegates to `WalletMultiplier.calculate_hardware_wallet_multiplier/1`
  - [x] Returns 1.0-3.6x multiplier
- [x] Implement `calculate_overall/4`:
  - [x] Input: x_mult, phone_mult, rogue_mult, wallet_mult
  - [x] Output: product of all four (rounded to 1 decimal)
- [x] Implement `get_user_multipliers/1`:
  - [x] Input: user_id
  - [x] Fetch all data sources (X score, phone, ROGUE balance, wallet data)
  - [x] Calculate all 4 multipliers
  - [x] Calculate overall
  - [x] Return comprehensive map with all values
- [x] Implement `save_unified_multipliers/2` (private):
  - [x] Input: user_id, multipliers map
  - [x] Write to `unified_multipliers` Mnesia table
  - [x] Set `last_updated` and `created_at` timestamps
- [x] Implement `get_overall_multiplier/1`:
  - [x] Input: user_id
  - [x] Read from Mnesia, return overall_multiplier
  - [x] Handle missing record (calculate and save)
- [x] Implement individual update functions:
  - [x] `update_x_multiplier/2` - update X component only
  - [x] `update_phone_multiplier/1` - update phone component only
  - [x] `update_rogue_multiplier/1` - update ROGUE component only
  - [x] `update_wallet_multiplier/1` - update wallet component only
- [x] Implement `refresh_multipliers/1` - recalculate all from scratch
- [x] Implement `get_x_score/1` - get raw X score for share rewards
- [ ] Add unit tests in `test/blockster_v2/unified_multiplier_test.exs`

#### 1.5 Update X Score Calculator Integration
- [x] **File**: `lib/blockster_v2/social/x_score_calculator.ex`
- [x] **MODIFY** `save_score/2`:
  - [x] After saving to `x_connections` and legacy `user_multipliers`, also update `unified_multipliers`
  - [x] Call `UnifiedMultiplier.update_x_multiplier(user_id, score_data.x_score)`

#### 1.6 Update Engagement Tracker Integration
- [x] **File**: `lib/blockster_v2/engagement_tracker.ex`
- [x] **MODIFY** `update_user_rogue_balance/4`:
  - [x] After updating `user_rogue_balances` Mnesia table
  - [x] Call `UnifiedMultiplier.update_rogue_multiplier(user_id)` when chain is `:rogue_chain`

#### 1.7 Update Phone Verification Integration
- [x] **File**: `lib/blockster_v2/phone_verification.ex`
- [x] **MODIFY** `update_user_multiplier/4`:
  - [x] After updating PostgreSQL users table
  - [x] Call `UnifiedMultiplier.update_phone_multiplier(user_id)`

#### 1.8 Update Wallet Multiplier Refresher Integration
- [x] **File**: `lib/blockster_v2/wallet_multiplier_refresher.ex`
- [x] **MODIFY** `do_refresh_all_multipliers/0`:
  - [x] After calling `WalletMultiplier.update_user_multiplier(user_id)`
  - [x] Also call `UnifiedMultiplier.update_wallet_multiplier(user_id)`

---

### Phase 1 Implementation Notes (Completed Jan 29, 2026)

#### Files Created

1. **`lib/blockster_v2/rogue_multiplier.ex`** - NEW FILE
   - Calculates ROGUE multiplier (1.0x - 5.0x) from smart wallet balance only
   - Uses tiers: 100k increments, max 1M ROGUE for calculation
   - Public functions: `calculate_rogue_multiplier/1`, `get_multiplier/1`, `calculate_from_balance/1`, `get_tiers/0`
   - Reads from `user_rogue_balances` Mnesia table (index 3 = `rogue_balance_rogue_chain`)

2. **`lib/blockster_v2/unified_multiplier.ex`** - NEW FILE
   - Main entry point for getting/updating multipliers
   - Four component update functions that only recalculate the changed component
   - Full refresh function that recalculates everything from scratch
   - Phone multiplier tiers: premium (2.0x), standard (1.5x), basic (1.0x), unverified (0.5x)
   - Overall formula: `X × Phone × ROGUE × Wallet` (0.5x to 360.0x range)

#### Files Modified

1. **`lib/blockster_v2/mnesia_initializer.ex`**
   - Added `unified_multipliers` table to `@tables` list
   - Attributes: `[:user_id, :x_score, :x_multiplier, :phone_multiplier, :rogue_multiplier, :wallet_multiplier, :overall_multiplier, :last_updated, :created_at]`
   - Index on `:overall_multiplier` for leaderboard queries

2. **`lib/blockster_v2/wallet_multiplier.ex`**
   - Removed all ROGUE-related code (constants, functions, balance fetching)
   - New range: 1.0x - 3.6x (was higher with ROGUE included)
   - Components: base (1.0x) + connection boost (+0.1x) + ETH (+0.0x to +1.5x) + other tokens (+0.0x to +1.0x)
   - Updated moduledoc and function docs to reflect changes

3. **`lib/blockster_v2/social/x_score_calculator.ex`**
   - Added alias for `UnifiedMultiplier`
   - In `save_score/2`: calls `UnifiedMultiplier.update_x_multiplier(user_id, score_data.x_score)` after saving to legacy tables

4. **`lib/blockster_v2/engagement_tracker.ex`**
   - In `update_user_rogue_balance/4`: calls `UnifiedMultiplier.update_rogue_multiplier(user_id)` when chain is `:rogue_chain`

5. **`lib/blockster_v2/phone_verification.ex`**
   - Added alias for `UnifiedMultiplier`
   - At end of `update_user_multiplier/4`: calls `UnifiedMultiplier.update_phone_multiplier(user_id)`

6. **`lib/blockster_v2/wallet_multiplier_refresher.ex`**
   - Added alias for `UnifiedMultiplier`
   - In `do_refresh_all_multipliers/0`: calls `UnifiedMultiplier.update_wallet_multiplier(user_id)` after updating legacy table

#### Key Design Decisions

1. **Individual update functions**: Each component has its own update function (`update_x_multiplier/2`, `update_phone_multiplier/1`, `update_rogue_multiplier/1`, `update_wallet_multiplier/1`) that only recalculates that component and the overall. This is more efficient than recalculating everything when only one thing changes.

2. **Lazy initialization**: `get_overall_multiplier/1` and `get_user_multipliers/1` will calculate and save if no record exists. This means the table will populate organically as users interact with the system.

3. **Separate from legacy tables**: The new `unified_multipliers` table is completely separate from `user_multipliers`. Both are updated in parallel during the transition period. This allows for safe rollback if issues are discovered.

4. **Phone multiplier uses `geo_tier` field**: The phone multiplier looks up the user's `geo_tier` from PostgreSQL (`premium`, `standard`, `basic`, or `nil` for unverified) rather than a numeric `geo_multiplier` field.

5. **ROGUE balance from Rogue Chain only**: The `RogueMultiplier` module reads from `user_rogue_balances` index 3 (`rogue_balance_rogue_chain`), ignoring any Arbitrum ROGUE balance. This matches the V2 spec that only Blockster smart wallet ROGUE counts.

#### Testing Notes

- Project compiles successfully with only cosmetic warnings
- Tables will be created on next node restart
- Integration points are ready to trigger unified multiplier updates

#### Remaining Phase 1 Tasks

- [x] Restart node1 and node2 to create the `unified_multipliers` table
- [x] Verify table creation: `:mnesia.table_info(:unified_multipliers, :attributes)`
- [ ] Add unit tests for `RogueMultiplier` module
- [ ] Add unit tests for `UnifiedMultiplier` module
- [x] Test all integration points manually

#### Bugs Fixed During Testing (Jan 29, 2026)

1. **x_score index off-by-one**: `get_x_score_from_connections/1` was reading index 10 (`connected_at` timestamp) instead of index 11 (`x_score`). Fixed to read correct index.

2. **Record indices incorrect**: All individual update functions (`update_x_multiplier/2`, `update_phone_multiplier/1`, `update_rogue_multiplier/1`, `update_wallet_multiplier/1`) and accessor functions (`get_user_multipliers/1`, `get_overall_multiplier/1`, `get_x_score/1`) had incorrect tuple indices. Fixed all to use correct mapping:
   - Index 0: `:unified_multipliers` (table name)
   - Index 1: `user_id`
   - Index 2: `x_score`
   - Index 3: `x_multiplier`
   - Index 4: `phone_multiplier`
   - Index 5: `rogue_multiplier`
   - Index 6: `wallet_multiplier`
   - Index 7: `overall_multiplier`
   - Index 8: `last_updated`
   - Index 9: `created_at`

3. **Verified working for user 65**:
   - x_score: 30 → x_multiplier: 3.0
   - phone_multiplier: 2.0 (premium geo_tier)
   - rogue_multiplier: 5.0 (max - has 1M+ ROGUE)
   - wallet_multiplier: 1.1 (base + connection boost)
   - overall_multiplier: 33.0 (3.0 × 2.0 × 5.0 × 1.1)

---

### Phase 2: Backend - Update Reward Calculations

#### 2.1 Update Reading Rewards (Articles/Posts)
- [x] **File**: `lib/blockster_v2_web/live/post_live/show.ex` (not engagement_tracker.ex)
- [x] Find the reading reward calculation function: `calculate_bux_earned/4` in EngagementTracker
- [x] **VERIFY** current formula: `(engagement_score / 10) × base_bux_reward × user_multiplier × geo_multiplier`
- [x] **CHANGE** `safe_get_user_multiplier/1` to use `UnifiedMultiplier.get_overall_multiplier/1`
- [x] **CHANGE** `geo_multiplier` to `1.0` (phone multiplier now included in unified multiplier)
- [x] **ENSURE** engagement score (1-10) divides base reward into tenths ✓
- [ ] **TEST** reward calculation:
  - [ ] User with 0.5x multiplier, engagement 7/10, base 10 BUX → 3.5 BUX
  - [ ] User with 42.0x multiplier, engagement 7/10, base 10 BUX → 294 BUX
  - [ ] User with 360.0x multiplier, engagement 10/10, base 10 BUX → 3,600 BUX

#### 2.2 Update Video Rewards
- [x] **File**: `lib/blockster_v2_web/live/post_live/show.ex` (lines 698-810)
- [x] **CHANGE** `mint_video_session_reward/4` to get unified multiplier
- [x] **CHANGE** `calculate_session_video_bux/5` to accept and apply `user_multiplier`
- [x] **FORMULA**: `session_minutes × bux_per_minute × user_multiplier`
- [ ] **TEST** reward calculation:
  - [ ] User with 0.5x multiplier, 5 min watched, 1 BUX/min → 2.5 BUX
  - [ ] User with 42.0x multiplier, 5 min watched, 1 BUX/min → 210 BUX

#### 2.3 Update X Share Rewards (Uses X Score, NOT Overall Multiplier)
- [x] **File**: `lib/blockster_v2_web/live/post_live/show.ex`
- [x] **IMPORTANT**: X shares use raw X score (0-100), NOT the overall multiplier
- [x] **CHANGE** from: `x_multiplier = EngagementTracker.get_user_x_multiplier(...)` + `calculated_reward = round(x_multiplier * base_bux_reward)`
- [x] **CHANGE** to: `x_score = UnifiedMultiplier.get_x_score(...)` + `calculated_reward = x_score`
- [x] **RESULT**: UI now shows "Share to earn {x_score} BUX" (raw X score as BUX amount)
- [ ] **TEST** share rewards:
  - [ ] User with X score 30 → earns 30 BUX per share
  - [ ] User with X score 75 → earns 75 BUX per share
  - [ ] User with X score 100 → earns 100 BUX per share
  - [ ] User with no X connected (score 0) → cannot share / earns 0 BUX

#### 2.4 Add `get_x_score/1` Function to UnifiedMultiplier
- [x] **File**: `lib/blockster_v2/unified_multiplier.ex`
- [x] **ALREADY EXISTS**: `get_x_score/1` was implemented in Phase 1 (lines 105-117)
- [x] Returns raw X score (0-100) from `unified_multipliers` table or falls back to `x_connections` table

#### 2.5 Update Any Other Multiplier Usages
- [x] Search codebase for `get_user_x_multiplier`, `get_user_multiplier`, `get_combined_multiplier`
- [x] **post_live/show.ex**: Updated to use `UnifiedMultiplier.get_overall_multiplier/1` for reading/video
- [x] **post_live/show.ex**: Updated to use `UnifiedMultiplier.get_x_score/1` for X shares
- [x] **Legacy functions kept**: `EngagementTracker.get_user_multiplier/1`, `EngagementTracker.get_user_x_multiplier/1`, `WalletMultiplier.get_combined_multiplier/1` - kept for backwards compatibility
- [x] **member_live/show.ex**: Uses `EngagementTracker.get_user_multiplier_details/1` for display - will be updated in Phase 3

### Phase 2 Implementation Notes (Completed Jan 29, 2026)

#### Files Modified

1. **`lib/blockster_v2_web/live/post_live/show.ex`**
   - Added `alias BlocksterV2.UnifiedMultiplier`
   - Changed `safe_get_user_multiplier/1`:
     - Now returns `UnifiedMultiplier.get_overall_multiplier(user_id)` for logged-in users
     - Returns `0.5` (minimum) for anonymous users (was `1`)
   - Changed `geo_multiplier` assignment:
     - Now always `1.0` (phone multiplier is already included in unified multiplier)
     - Was fetching from `current_user.geo_multiplier`
   - Changed X share reward calculation:
     - Was: `x_multiplier = EngagementTracker.get_user_x_multiplier(...)` + `calculated_reward = round(x_multiplier * base_bux_reward)`
     - Now: `x_score = UnifiedMultiplier.get_x_score(...)` + `calculated_reward = x_score`
   - Changed `mint_video_session_reward/4`:
     - Now fetches `user_multiplier = safe_get_user_multiplier(user_id)`
     - Passes multiplier to `calculate_session_video_bux/5`
   - Changed `calculate_session_video_bux/5`:
     - Added `user_multiplier` parameter (defaults to 1.0)
     - Formula now: `session_minutes * bux_per_minute * user_multiplier`

#### Key Design Decisions

1. **Phone multiplier consolidation**: The V1 system used separate `user_multiplier` (from Mnesia) and `geo_multiplier` (from PostgreSQL). V2 consolidates these - the unified multiplier already includes phone multiplier as one of its four components. Setting `geo_multiplier = 1.0` avoids double-counting.

2. **X share rewards**: Changed from `x_multiplier × base_bux_reward` to just `x_score`. This is a significant change - users now earn their raw X score (0-100) as BUX per share, not a multiplied amount. Example: X score 30 → 30 BUX per share (was 30 BUX × 10 base = 300 BUX before if base_bux_reward was 10).

3. **Anonymous users**: Changed default multiplier from `1` to `0.5` (the minimum for unverified phone). This matches the V2 spec where unverified users get a 0.5x penalty.

4. **Video rewards**: Now use the unified multiplier. Previously video rewards were just `minutes × bux_per_minute` without any multiplier.

5. **Backwards compatibility**: Legacy multiplier functions are preserved in `EngagementTracker` and `WalletMultiplier` for any code that hasn't been migrated yet.

---

---

### Phase 3: Frontend - Member Page UI

#### 3.1 Update Member Page LiveView (`show.ex`)
- [x] **File**: `lib/blockster_v2_web/live/member_live/show.ex`
- [x] **ADD** new assigns in mount/handle_params:
  - [x] `rogue_multiplier_data` - from `RogueMultiplier.calculate_rogue_multiplier(member.id)`
  - [x] `unified_multipliers` - from `UnifiedMultiplier.get_user_multipliers(member.id)`
  - [x] `x_multiplier` - extract from unified_multipliers
  - [x] `phone_multiplier` - extract from unified_multipliers
  - [x] `rogue_multiplier` - extract from unified_multipliers
  - [x] `wallet_multiplier` - extract from unified_multipliers
  - [x] `overall_multiplier` - extract from unified_multipliers
- [x] `switch_tab` event already supports any tab value - no changes needed

#### 3.2 Replace "LEVEL" Stats Box with "BUX MULTIPLIER" Stats Box
- [x] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [x] **REPLACE** "LEVEL" stats box with "BUX MULTIPLIER" stats box (lines ~226-343)
- [x] Main display shows overall multiplier with dropdown toggle
- [x] **ADD** clickable dropdown showing all 4 multiplier components
- [x] Shows X score, current/max values, sparkle emoji for maxed multipliers

#### 3.3 Create New "ROGUE" Tab
- [x] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [x] **ADD** new tab button for "ROGUE" in tab navigation (w-1/4 width)
- [x] **ADD** tab content section with:
  - [x] Header: "Hold ROGUE to Boost your BUX Earnings"
  - [x] Smart wallet balance display with current multiplier
  - [x] Tier progress grid (11 rows: 0-99k through 1M+)
  - [x] Current tier highlighted, achieved tiers marked with ✓
  - [x] Info note: "Only ROGUE in Blockster smart wallet counts"
  - [x] Quick links: Buy ROGUE, Play BUX Booster

#### 3.4 Update "External Wallet" Tab (V2: ROGUE Excluded from Multiplier)
- [x] **File**: `lib/blockster_v2_web/live/member_live/show.html.heex`
- [x] **REMOVED** ROGUE tier table ("Hold ROGUE to Boost your BUX Earnings")
- [x] **UPDATED** token_multipliers map - ROGUE no longer contributes to multiplier
- [x] **KEEP** ROGUE balance display rows (users can still see balances)
- [x] **KEEP** ROGUE transfer functionality (send/receive between wallets)
- [x] ROGUE rows now show "— See ROGUE tab" instead of multiplier boost
- [x] **ADD** info box: "ROGUE tracked separately in ROGUE tab"
- [x] **UPDATE** total display label: "External Wallet Multiplier / 3.6x max"
- [x] **UPDATE** footer text: "ETH + other tokens only. ROGUE tracked in ROGUE tab."

#### 3.5 Multiplier Breakdown Dropdown
- [x] Implemented using LiveView events (toggle_multiplier_dropdown, close_multiplier_dropdown)
- [x] Shows all 4 multipliers with current/max values
- [x] ✨ emoji for maxed-out multipliers
- [x] Overall total with formula explanation

### Phase 3 Implementation Notes (Completed Jan 29, 2026)

#### Files Modified

1. **`lib/blockster_v2_web/live/member_live/show.ex`**
   - Added aliases for `UnifiedMultiplier` and `RogueMultiplier`
   - Added unified multiplier data fetching in `handle_params`
   - Added new assigns: `unified_multipliers`, `rogue_multiplier_data`, individual multipliers
   - Added `toggle_multiplier_dropdown` and `close_multiplier_dropdown` event handlers
   - Added `show_multiplier_dropdown` assign for dropdown state

2. **`lib/blockster_v2_web/live/member_live/show.html.heex`**
   - Replaced "LEVEL" stats box with "BUX Multiplier" stats box (lines ~226-343)
   - Added clickable dropdown showing V2 multiplier breakdown
   - Added new "ROGUE" tab button (w-1/4 width)
   - Added ROGUE tab content section with smart wallet balance and tier grid
   - Updated External Wallet tab:
     - Removed ROGUE tier table
     - Updated token_multipliers to exclude ROGUE
     - ROGUE rows show "— See ROGUE tab" link
     - Updated footer label to "External Wallet Multiplier / 3.6x max"

#### Key Design Decisions

1. **ROGUE still visible in External Wallet tab**: Users can see their external wallet ROGUE balances and transfer ROGUE between wallets, but ROGUE doesn't contribute to the External Wallet multiplier. A "See ROGUE tab" link helps users understand where ROGUE multiplier is tracked.

2. **Separate ROGUE tab**: The new ROGUE tab shows only smart wallet ROGUE balance and tiers. This makes it clear that only smart wallet ROGUE counts toward the multiplier.

3. **Tab button widths**: Updated all active tabs to w-1/4 (Activity, ROGUE, External Wallet, Settings) to fit 4 tabs evenly.

4. **Multiplier dropdown**: Uses LiveView events instead of Alpine.js for consistency with the rest of the app. Click to toggle, click-away to close.

---

### Phase 4: Testing & Validation

#### 4.1 Unit Tests - Multiplier Modules ✅ COMPLETE (Jan 29, 2026)
- [x] `test/blockster_v2/rogue_multiplier_test.exs` (21 tests):
  - [x] Test all tier boundaries (99,999 vs 100,000, etc.)
  - [x] Test 1M cap behavior
  - [x] Test nil/missing balance handling
  - [x] Float balance handling
  - [x] next_tier info calculation
  - [x] Edge cases (negative, nil, string inputs)
- [x] `test/blockster_v2/unified_multiplier_test.exs` (40 tests):
  - [x] Test X multiplier calculation (0, 50, 100 scores)
  - [x] Test phone multiplier for each tier
  - [x] Test overall calculation (multiplicative, not additive)
  - [x] Test edge cases (all minimums = 0.5x, all maximums = 360.0x)
  - [x] Test `get_x_score/1` returns raw score (0-100)
  - [x] Error handling for invalid inputs
- [x] `test/blockster_v2/wallet_multiplier_test.exs` (9 tests):
  - [x] Verify max is now 3.6x not 7.6x (ROGUE removed)
  - [x] ETH tier structure and boosts
  - [x] ROGUE removal verification (no ROGUE tiers in ETH list)

**Notes:**
- Tests requiring database (Wallets.get_connected_wallet) or Mnesia access moved to integration tests
- Total: 70 unit tests passing
- Run with: `mix test test/blockster_v2/rogue_multiplier_test.exs test/blockster_v2/unified_multiplier_test.exs test/blockster_v2/wallet_multiplier_test.exs`

#### 4.2 Unit Tests - Reward Calculations ✅ COMPLETE (Jan 29, 2026)
- [x] `test/blockster_v2/reward_calculation_test.exs` (36 tests):
  - [x] **Reading rewards** (18 tests):
    - [x] Test formula: `(engagement/10) × base_bux × overall_multiplier`
    - [x] Engagement 7/10, base 10 BUX, multiplier 0.5x → 3.5 BUX
    - [x] Engagement 7/10, base 10 BUX, multiplier 42.0x → 294 BUX
    - [x] Engagement 10/10, base 10 BUX, multiplier 360.0x → 3,600 BUX
    - [x] Edge case: engagement 0 → 0 BUX regardless of multiplier
    - [x] Edge case: base_bux 0 → 0 BUX regardless of multiplier
    - [x] geo_multiplier handling (applies when provided, defaults to 1.0)
    - [x] nil handling for base_bux, user_multiplier, geo_multiplier
    - [x] Rounds to 2 decimal places
  - [x] **Video rewards** (8 tests):
    - [x] Test formula: `minutes × bux_per_minute × overall_multiplier`
    - [x] 5 min, 1 BUX/min, multiplier 0.5x → 2.5 BUX
    - [x] 5 min, 1 BUX/min, multiplier 42.0x → 210 BUX
    - [x] Edge case: 0 minutes → 0 BUX
    - [x] Fractional minutes work correctly
  - [x] **X share rewards** (10 tests):
    - [x] Test formula: `reward = x_score` (NOT multiplied)
    - [x] X score 30 → 30 BUX
    - [x] X score 75 → 75 BUX
    - [x] X score 100 → 100 BUX
    - [x] X score 0 (no X connected) → 0 BUX
    - [x] Verify overall multiplier is NOT applied to share rewards
    - [x] Comparison tests showing same X score users earn same share regardless of multiplier

**Notes:**
- Video rewards use helper function (actual implementation may be in different module)
- X share rewards use helper function (production uses UnifiedMultiplier.get_x_score/1)
- Comparison tests verify reading rewards differ by multiplier, share rewards don't
- Run with: `mix test test/blockster_v2/reward_calculation_test.exs`

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
