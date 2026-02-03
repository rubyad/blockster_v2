# BuxBooster Betting Stats Architecture

## Overview

BuxBooster supports two currencies for betting:
- **BUX** - ERC-20 token
- **ROGUE** - Native gas token of Rogue Chain

Stats for these currencies are stored in **different contracts** with **different data structures**, which creates complexity when querying player statistics.

---

## How Stats Are Recorded (Current System V6)

### ROGUE Bet Flow

When a user places a ROGUE bet, the following happens:

1. **User calls `placeBetROGUE()`** on BuxBoosterGame contract
   - Sends native ROGUE with the transaction (`msg.value`)
   - BuxBoosterGame forwards ROGUE to ROGUEBankroll

2. **On settlement, `settleBetROGUE()` is called**
   - BuxBoosterGame calls ROGUEBankroll to handle payout
   - **ROGUEBankroll updates its own stats** (ROGUE-only):
     ```solidity
     // In ROGUEBankroll._processBuxBoosterBet()
     BuxBoosterPlayerStats storage playerStats = buxBoosterPlayerStats[player];
     playerStats.totalBets++;
     playerStats.totalWagered += amount;
     if (won) {
         playerStats.wins++;
         playerStats.totalWinnings += profit;
     } else {
         playerStats.losses++;
         playerStats.totalLosses += amount;
     }

     // Also updates global accounting
     buxBoosterAccounting.totalBets++;
     buxBoosterAccounting.totalVolumeWagered += amount;
     // ... etc
     ```
   - **BuxBoosterGame ALSO updates its combined stats** (the problem!):
     ```solidity
     // In BuxBoosterGame._processSettlementROGUE()
     PlayerStats storage stats = playerStats[bet.player];  // Combined mapping!
     stats.totalBets++;
     stats.totalStaked += bet.amount;
     stats.overallProfitLoss += profit;
     stats.betsPerDifficulty[diffIndex]++;
     stats.profitLossPerDifficulty[diffIndex] += profit;
     ```

**Result**: ROGUE bets are recorded in TWO places:
- ✅ `ROGUEBankroll.buxBoosterPlayerStats` - ROGUE only (correct)
- ❌ `BuxBoosterGame.playerStats` - Combined with BUX (problematic)

### BUX Bet Flow

When a user places a BUX bet:

1. **User approves BUX spending** then calls `placeBet()` on BuxBoosterGame
   - BuxBoosterGame pulls BUX from user via `transferFrom()`

2. **On settlement, `settleBet()` is called**
   - BuxBoosterGame handles payout directly (no external contract)
   - **Only updates combined stats**:
     ```solidity
     // In BuxBoosterGame._processSettlement()
     PlayerStats storage stats = playerStats[bet.player];  // Combined mapping!
     stats.totalBets++;
     stats.totalStaked += bet.amount;
     stats.overallProfitLoss += profit;
     stats.betsPerDifficulty[diffIndex]++;
     stats.profitLossPerDifficulty[diffIndex] += profit;
     ```

**Result**: BUX bets are recorded in ONE place:
- ❌ `BuxBoosterGame.playerStats` - Combined with ROGUE (no way to separate)

### The Data Problem Visualized

```
┌─────────────────────────────────────────────────────────────────┐
│                     BuxBoosterGame Contract                      │
│                                                                  │
│  playerStats mapping (COMBINED - contains both BUX and ROGUE)   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Player 0xABC:                                            │    │
│  │   totalBets: 115 (79 BUX + 36 ROGUE - can't separate!)  │    │
│  │   totalStaked: 12,805,754 (mixed BUX + ROGUE values)    │    │
│  │   overallProfitLoss: +2,405,843 (combined P/L)          │    │
│  │   betsPerDifficulty[9]: [combined counts...]            │    │
│  │   profitLossPerDifficulty[9]: [combined P/L...]         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  NO global BUX accounting exists!                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     ROGUEBankroll Contract                       │
│                                                                  │
│  buxBoosterPlayerStats mapping (ROGUE ONLY - clean!)            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Player 0xABC:                                            │    │
│  │   totalBets: 36                                          │    │
│  │   wins: 15                                               │    │
│  │   losses: 21                                             │    │
│  │   totalWagered: 3,614,563 ROGUE                         │    │
│  │   totalWinnings: 552,006 ROGUE                          │    │
│  │   totalLosses: 2,552,569 ROGUE                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  buxBoosterAccounting (ROGUE ONLY - clean!)                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │   totalBets: 563                                         │    │
│  │   totalWins: 286                                         │    │
│  │   totalLosses: 277                                       │    │
│  │   totalVolumeWagered: 296,475,589 ROGUE                 │    │
│  │   totalPayouts: 292,666,355 ROGUE                       │    │
│  │   totalHouseProfit: 3,809,233 ROGUE                     │    │
│  │   largestWin: 14,464,000 ROGUE                          │    │
│  │   largestBet: 20,000,000 ROGUE                          │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Current Workaround: Calculate BUX by Subtraction

Since ROGUE stats are tracked separately, we can derive BUX stats:

```
BUX Stats = Combined Stats (BuxBoosterGame) - ROGUE Stats (ROGUEBankroll)

BUX totalBets = combined.totalBets - rogue.totalBets
BUX totalWagered = combined.totalStaked - rogue.totalWagered
BUX netPnL = combined.overallProfitLoss - (rogue.totalWinnings - rogue.totalLosses)
```

**Limitations of this workaround:**
- No BUX wins/losses count (only ROGUE has this)
- No BUX global accounting (house profit, largest bet, etc.)
- Per-difficulty breakdown cannot be separated
- Requires 2 contract calls + math for every query

---

## Contract Architecture

### BuxBoosterGame Contract
- **Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B`
- **Network**: Rogue Chain Mainnet (560013)
- **Stores**: **Combined** BUX + ROGUE stats in a single `playerStats` mapping

```solidity
struct PlayerStats {
    uint256 totalBets;
    uint256 totalStaked;
    int256 overallProfitLoss;
    uint256[9] betsPerDifficulty;      // Count of bets at each difficulty
    int256[9] profitLossPerDifficulty; // P/L at each difficulty
}

mapping(address => PlayerStats) public playerStats;
```

**Important**: Both `_processSettlement()` (for BUX) and `_processSettlementROGUE()` (for ROGUE) write to this same mapping. Therefore, `getPlayerStats()` returns **combined** totals, not BUX-only stats.

### ROGUEBankroll Contract
- **Address**: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
- **Network**: Rogue Chain Mainnet (560013)
- **Stores**: **ROGUE-only** stats

```solidity
struct BuxBoosterPlayerStats {
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 totalWagered;
    uint256 totalWinnings;  // Total profit from wins
    uint256 totalLosses;    // Total losses from losing bets
}

mapping(address => BuxBoosterPlayerStats) public buxBoosterPlayerStats;

struct BuxBoosterAccounting {
    uint256 totalBets;
    uint256 totalWins;
    uint256 totalLosses;
    uint256 totalVolumeWagered;
    uint256 totalPayouts;
    int256 totalHouseProfit;
    uint256 largestWin;
    uint256 largestBet;
}

BuxBoosterAccounting public buxBoosterAccounting;
```

## How to Query Stats Correctly

### ROGUE Stats (Direct Query)

ROGUE stats can be queried directly from ROGUEBankroll:

```javascript
const ROGUE_ABI = [
  "function buxBoosterPlayerStats(address) external view returns (uint256 totalBets, uint256 wins, uint256 losses, uint256 totalWagered, uint256 totalWinnings, uint256 totalLosses)"
];

const rogueBankroll = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_ABI, provider);
const rogueStats = await rogueBankroll.buxBoosterPlayerStats(playerAddress);

// Net P/L = totalWinnings - totalLosses
const rogueNetPnL = BigInt(rogueStats.totalWinnings) - BigInt(rogueStats.totalLosses);
```

### BUX Stats (Calculated)

BUX stats must be **calculated** by subtracting ROGUE stats from combined stats:

```javascript
const COMBINED_ABI = [
  "function getPlayerStats(address player) external view returns (uint256 totalBets, uint256 totalStaked, int256 overallProfitLoss, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)"
];

const buxBooster = new ethers.Contract(BUX_BOOSTER_GAME_ADDRESS, COMBINED_ABI, provider);
const combined = await buxBooster.getPlayerStats(playerAddress);

// BUX = Combined - ROGUE
const buxBets = BigInt(combined.totalBets) - BigInt(rogueStats.totalBets);
const buxStaked = BigInt(combined.totalStaked) - BigInt(rogueStats.totalWagered);
const buxPnL = BigInt(combined.overallProfitLoss) - rogueNetPnL;
```

### Global Stats

#### ROGUE Global Stats (Direct Query)
```javascript
const ROGUE_ACCOUNTING_ABI = [
  "function buxBoosterAccounting() external view returns (uint256 totalBets, uint256 totalWins, uint256 totalLosses, uint256 totalVolumeWagered, uint256 totalPayouts, int256 totalHouseProfit, uint256 largestWin, uint256 largestBet)"
];

const stats = await rogueBankroll.buxBoosterAccounting();
```

#### BUX Global Stats
BuxBoosterGame does not have a separate global accounting struct. To get BUX-only global stats, you would need to:
1. Query all `BetSettled` events from the contract
2. Filter by token address (BUX vs ROGUE)
3. Aggregate the results

Alternatively, track BUX global stats off-chain in the application database.

## Summary Table

| Stat Type | BUX | ROGUE |
|-----------|-----|-------|
| Per-player stats | Calculate: `combined - ROGUE` | Direct: `buxBoosterPlayerStats()` |
| Global stats | Not available on-chain | Direct: `buxBoosterAccounting()` |
| Per-difficulty breakdown | Not separable* | Not available** |

\* The per-difficulty arrays in BuxBoosterGame contain combined BUX+ROGUE data
\** ROGUEBankroll does not track per-difficulty stats

## Contract ABIs Reference

### BuxBoosterGame (Combined Stats)
```javascript
const BUX_BOOSTER_ABI = [
  // Player stats (COMBINED BUX + ROGUE)
  "function getPlayerStats(address player) external view returns (uint256 totalBets, uint256 totalStaked, int256 overallProfitLoss, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)",

  // Token config (for house balance)
  "function tokenConfigs(address token) external view returns (bool enabled, uint256 houseBalance)"
];
```

### ROGUEBankroll (ROGUE-Only Stats)
```javascript
const ROGUE_BANKROLL_ABI = [
  // Player stats (ROGUE only)
  "function buxBoosterPlayerStats(address) external view returns (uint256 totalBets, uint256 wins, uint256 losses, uint256 totalWagered, uint256 totalWinnings, uint256 totalLosses)",

  // Global accounting (ROGUE only)
  "function buxBoosterAccounting() external view returns (uint256 totalBets, uint256 totalWins, uint256 totalLosses, uint256 totalVolumeWagered, uint256 totalPayouts, int256 totalHouseProfit, uint256 largestWin, uint256 largestBet)"
];
```

## Difficulty Level Mapping

The per-difficulty arrays use index 0-8, mapping to difficulty levels -4 to +4:

| Index | Difficulty | Mode | Flips | Multiplier |
|-------|------------|------|-------|------------|
| 0 | -4 | Win One | 5 | 1.02x |
| 1 | -3 | Win One | 4 | 1.05x |
| 2 | -2 | Win One | 3 | 1.13x |
| 3 | -1 | Win One | 2 | 1.32x |
| 4 | 0 | Single Flip | 1 | 1.98x |
| 5 | +1 | Win All | 2 | 3.96x |
| 6 | +2 | Win All | 3 | 7.92x |
| 7 | +3 | Win All | 4 | 15.84x |
| 8 | +4 | Win All | 5 | 31.68x |

---

# Admin Stats Dashboard Implementation Plan

## Overview

Build an admin area in the Blockster Phoenix app to display:
1. **Global betting stats** for BUX and ROGUE
2. **Per-user betting stats** for all players who have placed bets
3. **Leaderboards** (biggest winners, biggest losers, most active)

## Phase 1: Backend - Stats Fetching Service

### 1.1 Create BuxBoosterStats Module

**File**: `lib/blockster_v2/bux_booster_stats.ex`

This module handles all contract queries and stat calculations.

```elixir
defmodule BlocksterV2.BuxBoosterStats do
  @moduledoc """
  Fetches and calculates BuxBooster betting statistics from on-chain contracts.

  IMPORTANT: BUX stats must be calculated by subtracting ROGUE stats from combined stats,
  because BuxBoosterGame.playerStats contains combined BUX+ROGUE data.
  """

  @bux_booster_game "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"
  @rogue_bankroll "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  @rpc_url "https://rpc.roguechain.io/rpc"

  @doc """
  Get ROGUE global betting stats from ROGUEBankroll.buxBoosterAccounting()
  """
  def get_rogue_global_stats()

  @doc """
  Get ROGUE stats for a specific player from ROGUEBankroll.buxBoosterPlayerStats()
  """
  def get_rogue_player_stats(wallet_address)

  @doc """
  Get combined (BUX+ROGUE) stats for a player from BuxBoosterGame.getPlayerStats()
  """
  def get_combined_player_stats(wallet_address)

  @doc """
  Calculate BUX-only stats by subtracting ROGUE from combined.
  Returns {:ok, bux_stats} or {:error, reason}
  """
  def get_bux_player_stats(wallet_address)

  @doc """
  Get complete stats for a player (both BUX and ROGUE separated).
  """
  def get_player_stats(wallet_address)

  @doc """
  Get list of all players who have placed bets.
  Queries BetPlaced events from BuxBoosterGame contract.
  """
  def get_all_players()

  @doc """
  Get stats for all players (paginated).
  """
  def get_all_player_stats(opts \\ [])
end
```

### 1.2 Contract Interaction via Req

Use the existing `Req` library (already in project) for JSON-RPC calls:

```elixir
# No new dependencies needed - Req is already in mix.exs

# Example call
def get_rogue_global_stats do
  # Function selector for buxBoosterAccounting()
  data = "0x..." # ABI-encoded call

  body = %{
    jsonrpc: "2.0",
    method: "eth_call",
    params: [%{to: @rogue_bankroll, data: data}, "latest"],
    id: 1
  }

  case Req.post(@rpc_url, json: body, receive_timeout: 10_000) do
    {:ok, %{status: 200, body: %{"result" => result}}} ->
      decode_accounting_result(result)
    {:ok, %{body: %{"error" => error}}} ->
      {:error, error}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 1.3 Caching Layer

Stats don't need real-time updates. Cache in ETS or Mnesia:

```elixir
defmodule BlocksterV2.BuxBoosterStats.Cache do
  use GenServer

  @refresh_interval :timer.minutes(5)

  # Cache global stats
  # Cache per-player stats with TTL
  # Refresh on demand or periodically
end
```

## Phase 2: Backend - Player Discovery

### 2.1 Index Players from Events

To get a list of all players, we need to query historical `BetPlaced` events:

```elixir
defmodule BlocksterV2.BuxBoosterStats.PlayerIndex do
  @moduledoc """
  Indexes all players who have placed bets by scanning BetPlaced events.
  Stores player addresses in Mnesia for fast lookups.
  """

  # Mnesia table: :bux_booster_players
  # Fields: {wallet_address, first_bet_block, last_bet_block, last_indexed_at}

  def index_players_from_events(from_block \\ 0)
  def get_all_player_addresses()
  def get_player_count()
end
```

### 2.2 Mnesia Table for Players

Add to `MnesiaInitializer`:

```elixir
:mnesia.create_table(:bux_booster_players, [
  attributes: [:wallet_address, :first_bet_block, :last_bet_block, :total_bets_indexed],
  disc_copies: [node()],
  type: :set
])
```

## Phase 3: Admin LiveView Pages - Detailed Implementation

### 3.1 Route Structure

```elixir
# In router.ex
scope "/admin", BlocksterV2Web.Admin do
  pipe_through [:browser, :require_admin]

  live "/stats", StatsLive.Index, :index
  live "/stats/players", StatsLive.Players, :index
  live "/stats/players/:address", StatsLive.PlayerDetail, :show
end
```

### 3.2 How the Admin Area Queries Each Contract (Post-V7)

After the V7 upgrade, both BUX and ROGUE have their own dedicated stats on-chain.

#### Query BUX Global Stats

```elixir
def get_bux_global_stats do
  # Call BuxBoosterGame.getBuxAccounting()
  {:ok, result} = call_contract(
    @bux_booster_game_address,
    "getBuxAccounting()",
    []
  )

  %{
    total_bets: decode_uint(result, 0),
    total_wins: decode_uint(result, 1),
    total_losses: decode_uint(result, 2),
    total_volume_wagered: decode_uint(result, 3),
    total_payouts: decode_uint(result, 4),
    total_house_profit: decode_int(result, 5),
    largest_win: decode_uint(result, 6),
    largest_bet: decode_uint(result, 7)
  }
end
```

#### Query ROGUE Global Stats

```elixir
def get_rogue_global_stats do
  # Call ROGUEBankroll.buxBoosterAccounting()
  {:ok, result} = call_contract(
    @rogue_bankroll_address,
    "buxBoosterAccounting()",
    []
  )

  %{
    total_bets: decode_uint(result, 0),
    total_wins: decode_uint(result, 1),
    total_losses: decode_uint(result, 2),
    total_volume_wagered: decode_uint(result, 3),
    total_payouts: decode_uint(result, 4),
    total_house_profit: decode_int(result, 5),
    largest_win: decode_uint(result, 6),
    largest_bet: decode_uint(result, 7)
  }
end
```

#### Query BUX Player Stats

```elixir
def get_bux_player_stats(wallet_address) do
  # Call BuxBoosterGame.getBuxPlayerStats(address)
  {:ok, result} = call_contract(
    @bux_booster_game_address,
    "getBuxPlayerStats(address)",
    [wallet_address]
  )

  total_bets = decode_uint(result, 0)
  wins = decode_uint(result, 1)
  losses = decode_uint(result, 2)
  total_wagered = decode_uint(result, 3)
  total_winnings = decode_uint(result, 4)
  total_losses_amount = decode_uint(result, 5)

  %{
    total_bets: total_bets,
    wins: wins,
    losses: losses,
    total_wagered: total_wagered,
    total_winnings: total_winnings,
    total_losses: total_losses_amount,
    bets_per_difficulty: decode_uint_array(result, 6, 9),
    pnl_per_difficulty: decode_int_array(result, 7, 9),
    # Calculated fields
    win_rate: if(total_bets > 0, do: wins / total_bets * 100, else: 0),
    net_pnl: total_winnings - total_losses_amount
  }
end
```

#### Query ROGUE Player Stats

```elixir
def get_rogue_player_stats(wallet_address) do
  # Call ROGUEBankroll.buxBoosterPlayerStats(address)
  {:ok, result} = call_contract(
    @rogue_bankroll_address,
    "buxBoosterPlayerStats(address)",
    [wallet_address]
  )

  total_bets = decode_uint(result, 0)
  wins = decode_uint(result, 1)
  losses = decode_uint(result, 2)
  total_wagered = decode_uint(result, 3)
  total_winnings = decode_uint(result, 4)
  total_losses_amount = decode_uint(result, 5)

  %{
    total_bets: total_bets,
    wins: wins,
    losses: losses,
    total_wagered: total_wagered,
    total_winnings: total_winnings,
    total_losses: total_losses_amount,
    # Calculated fields
    win_rate: if(total_bets > 0, do: wins / total_bets * 100, else: 0),
    net_pnl: total_winnings - total_losses_amount
  }
end
```

#### Get Complete Player Stats (Both Currencies)

```elixir
def get_player_stats(wallet_address) do
  # Run both queries in parallel
  tasks = [
    Task.async(fn -> get_bux_player_stats(wallet_address) end),
    Task.async(fn -> get_rogue_player_stats(wallet_address) end)
  ]

  [bux_result, rogue_result] = Task.await_many(tasks, 10_000)

  %{
    wallet: wallet_address,
    bux: bux_result,
    rogue: rogue_result,
    combined: %{
      total_bets: bux_result.total_bets + rogue_result.total_bets,
      total_wins: bux_result.wins + rogue_result.wins,
      total_losses: bux_result.losses + rogue_result.losses
    }
  }
end
```

### 3.3 Global Stats Page

**File**: `lib/blockster_v2_web/live/admin/stats_live/index.ex`

```elixir
defmodule BlocksterV2Web.Admin.StatsLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(
      bux_stats: nil,
      rogue_stats: nil,
      house_balances: nil,
      loading: true,
      last_updated: nil
    )

    if connected?(socket) do
      send(self(), :load_stats)
    end

    {:ok, socket}
  end

  def handle_info(:load_stats, socket) do
    socket = socket
    |> start_async(:fetch_bux_global, fn -> BuxBoosterStats.get_bux_global_stats() end)
    |> start_async(:fetch_rogue_global, fn -> BuxBoosterStats.get_rogue_global_stats() end)
    |> start_async(:fetch_house_balances, fn -> BuxBoosterStats.get_house_balances() end)

    {:noreply, socket}
  end

  def handle_async(:fetch_bux_global, {:ok, stats}, socket) do
    {:noreply, assign(socket, bux_stats: stats)}
  end

  def handle_async(:fetch_rogue_global, {:ok, stats}, socket) do
    {:noreply, assign(socket, rogue_stats: stats, loading: false, last_updated: DateTime.utc_now())}
  end

  def handle_async(:fetch_house_balances, {:ok, balances}, socket) do
    {:noreply, assign(socket, house_balances: balances)}
  end

  def handle_event("refresh", _params, socket) do
    send(self(), :load_stats)
    {:noreply, assign(socket, loading: true)}
  end
end
```

### 3.4 UI Display - Global Stats Page

**What the UI Shows:**

```
┌────────────────────────────────────────────────────────────────────────────┐
│  BuxBooster Admin Stats                                    [↻ Refresh]     │
│  Last updated: 2 minutes ago                                               │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐         │
│  │  🔵 BUX Betting             │  │  🟡 ROGUE Betting            │         │
│  │  (from BuxBoosterGame)      │  │  (from ROGUEBankroll)        │         │
│  ├─────────────────────────────┤  ├─────────────────────────────┤         │
│  │  Total Bets      1,245      │  │  Total Bets      563         │         │
│  │  Wins            612        │  │  Wins            286         │         │
│  │  Losses          633        │  │  Losses          277         │         │
│  │  Win Rate        49.16%     │  │  Win Rate        50.80%      │         │
│  │  ───────────────────────    │  │  ───────────────────────     │         │
│  │  Volume Wagered             │  │  Volume Wagered              │         │
│  │    125,847,291 BUX          │  │    296,475,589 ROGUE         │         │
│  │  Total Payouts              │  │  Total Payouts               │         │
│  │    124,123,456 BUX          │  │    292,666,356 ROGUE         │         │
│  │  House Profit               │  │  House Profit                │         │
│  │    +1,723,835 BUX ✅        │  │    +3,809,233 ROGUE ✅       │         │
│  │  ───────────────────────    │  │  ───────────────────────     │         │
│  │  Largest Bet                │  │  Largest Bet                 │         │
│  │    5,000,000 BUX            │  │    20,000,000 ROGUE          │         │
│  │  Largest Win                │  │  Largest Win                 │         │
│  │    3,200,000 BUX            │  │    14,464,000 ROGUE          │         │
│  └─────────────────────────────┘  └─────────────────────────────┘         │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  House Balances                                                      │  │
│  ├─────────────────────────────────────────────────────────────────────┤  │
│  │  BUX House:    59,704.26 BUX        ROGUE House:  500,000,000 ROGUE │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

**Template**: `lib/blockster_v2_web/live/admin/stats_live/index.html.heex`

```heex
<div class="p-6 max-w-6xl mx-auto">
  <!-- Header -->
  <div class="flex justify-between items-center mb-6">
    <div>
      <h1 class="text-2xl font-haas_medium_65">BuxBooster Admin Stats</h1>
      <%= if @last_updated do %>
        <p class="text-sm text-gray-500">Last updated: <%= Timex.from_now(@last_updated) %></p>
      <% end %>
    </div>
    <button phx-click="refresh" class="px-4 py-2 bg-gray-100 rounded-lg hover:bg-gray-200 cursor-pointer">
      <%= if @loading do %>
        <span class="animate-spin">↻</span> Loading...
      <% else %>
        ↻ Refresh
      <% end %>
    </button>
  </div>

  <!-- Stats Cards Grid -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">

    <!-- BUX Stats Card -->
    <div class="bg-white rounded-lg shadow p-6">
      <div class="flex items-center gap-2 mb-4">
        <span class="text-2xl">🔵</span>
        <h2 class="text-lg font-haas_medium_65">BUX Betting</h2>
      </div>

      <%= if @bux_stats do %>
        <dl class="space-y-3">
          <div class="grid grid-cols-3 gap-4 pb-3 border-b">
            <div>
              <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
              <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@bux_stats.total_bets) %></dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Wins</dt>
              <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_wins) %></dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Losses</dt>
              <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_losses) %></dd>
            </div>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Player Win Rate</dt>
            <dd class="font-medium"><%= Float.round(@bux_stats.total_wins / max(@bux_stats.total_bets, 1) * 100, 2) %>%</dd>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Volume Wagered</dt>
            <dd class="font-medium"><%= format_bux(@bux_stats.total_volume_wagered) %> BUX</dd>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Total Payouts</dt>
            <dd class="font-medium"><%= format_bux(@bux_stats.total_payouts) %> BUX</dd>
          </div>

          <div class="flex justify-between items-center pt-3 border-t">
            <dt class="text-gray-500 font-medium">House Profit</dt>
            <dd class={"text-xl font-bold #{if @bux_stats.total_house_profit >= 0, do: "text-green-600", else: "text-red-600"}"}>
              <%= if @bux_stats.total_house_profit >= 0, do: "+", else: "" %><%= format_bux(@bux_stats.total_house_profit) %> BUX
            </dd>
          </div>

          <div class="grid grid-cols-2 gap-4 pt-3 border-t">
            <div>
              <dt class="text-xs text-gray-500 uppercase">Largest Bet</dt>
              <dd class="font-medium"><%= format_bux(@bux_stats.largest_bet) %> BUX</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Largest Win</dt>
              <dd class="font-medium"><%= format_bux(@bux_stats.largest_win) %> BUX</dd>
            </div>
          </div>
        </dl>
      <% else %>
        <div class="animate-pulse space-y-3">
          <div class="h-8 bg-gray-200 rounded w-1/2"></div>
          <div class="h-4 bg-gray-200 rounded w-3/4"></div>
        </div>
      <% end %>
    </div>

    <!-- ROGUE Stats Card -->
    <div class="bg-white rounded-lg shadow p-6">
      <div class="flex items-center gap-2 mb-4">
        <span class="text-2xl">🟡</span>
        <h2 class="text-lg font-haas_medium_65">ROGUE Betting</h2>
      </div>

      <%= if @rogue_stats do %>
        <dl class="space-y-3">
          <div class="grid grid-cols-3 gap-4 pb-3 border-b">
            <div>
              <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
              <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_bets) %></dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Wins</dt>
              <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_wins) %></dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Losses</dt>
              <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_losses) %></dd>
            </div>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Player Win Rate</dt>
            <dd class="font-medium"><%= Float.round(@rogue_stats.total_wins / max(@rogue_stats.total_bets, 1) * 100, 2) %>%</dd>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Volume Wagered</dt>
            <dd class="font-medium"><%= format_rogue(@rogue_stats.total_volume_wagered) %> ROGUE</dd>
          </div>

          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Total Payouts</dt>
            <dd class="font-medium"><%= format_rogue(@rogue_stats.total_payouts) %> ROGUE</dd>
          </div>

          <div class="flex justify-between items-center pt-3 border-t">
            <dt class="text-gray-500 font-medium">House Profit</dt>
            <dd class={"text-xl font-bold #{if @rogue_stats.total_house_profit >= 0, do: "text-green-600", else: "text-red-600"}"}>
              <%= if @rogue_stats.total_house_profit >= 0, do: "+", else: "" %><%= format_rogue(@rogue_stats.total_house_profit) %> ROGUE
            </dd>
          </div>

          <div class="grid grid-cols-2 gap-4 pt-3 border-t">
            <div>
              <dt class="text-xs text-gray-500 uppercase">Largest Bet</dt>
              <dd class="font-medium"><%= format_rogue(@rogue_stats.largest_bet) %> ROGUE</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 uppercase">Largest Win</dt>
              <dd class="font-medium"><%= format_rogue(@rogue_stats.largest_win) %> ROGUE</dd>
            </div>
          </div>
        </dl>
      <% else %>
        <div class="animate-pulse space-y-3">
          <div class="h-8 bg-gray-200 rounded w-1/2"></div>
          <div class="h-4 bg-gray-200 rounded w-3/4"></div>
        </div>
      <% end %>
    </div>
  </div>

  <!-- House Balances -->
  <div class="bg-white rounded-lg shadow p-6">
    <h2 class="text-lg font-haas_medium_65 mb-4">House Balances</h2>
    <%= if @house_balances do %>
      <div class="grid grid-cols-2 gap-6">
        <div class="p-4 bg-blue-50 rounded-lg">
          <dt class="text-sm text-blue-600 uppercase">BUX House Balance</dt>
          <dd class="text-2xl font-bold text-blue-800"><%= format_bux(@house_balances.bux) %> BUX</dd>
        </div>
        <div class="p-4 bg-yellow-50 rounded-lg">
          <dt class="text-sm text-yellow-600 uppercase">ROGUE House Balance</dt>
          <dd class="text-2xl font-bold text-yellow-800"><%= format_rogue(@house_balances.rogue) %> ROGUE</dd>
        </div>
      </div>
    <% else %>
      <div class="animate-pulse h-24 bg-gray-200 rounded"></div>
    <% end %>
  </div>
</div>
```

### 3.5 UI Display - Player Stats Page

**What the UI Shows for a Single Player:**

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Player Stats                                                              │
│  0x14C21eFf226D98D324CD2478A8579a0e63412d15                                │
│  [View on Roguescan ↗]                                                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐         │
│  │  🔵 BUX Stats               │  │  🟡 ROGUE Stats              │         │
│  │  (from BuxBoosterGame)      │  │  (from ROGUEBankroll)        │         │
│  ├─────────────────────────────┤  ├─────────────────────────────┤         │
│  │  Total Bets      79         │  │  Total Bets      36          │         │
│  │  Wins            42         │  │  Wins            15          │         │
│  │  Losses          37         │  │  Losses          21          │         │
│  │  Win Rate        53.16%     │  │  Win Rate        41.67%      │         │
│  │  ───────────────────────    │  │  ───────────────────────     │         │
│  │  Total Wagered              │  │  Total Wagered               │         │
│  │    9,191 BUX                │  │    3,614,563 ROGUE           │         │
│  │  Total Winnings             │  │  Total Winnings              │         │
│  │    5,123 BUX                │  │    552,006 ROGUE             │         │
│  │  Total Losses               │  │  Total Losses                │         │
│  │    717 BUX                  │  │    2,552,569 ROGUE           │         │
│  │  ───────────────────────    │  │  ───────────────────────     │         │
│  │  Net Profit/Loss            │  │  Net Profit/Loss             │         │
│  │    +4,406 BUX ✅            │  │    -2,000,563 ROGUE ❌       │         │
│  └─────────────────────────────┘  └─────────────────────────────┘         │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  BUX Per-Difficulty Breakdown                                        │  │
│  ├───────────────────┬────────┬──────────┬──────────────────────────────┤  │
│  │  Difficulty       │  Bets  │  Win Rate│  P/L                         │  │
│  ├───────────────────┼────────┼──────────┼──────────────────────────────┤  │
│  │  Win One 5-flip   │   12   │  91.7%   │  +234 BUX                    │  │
│  │  Win One 4-flip   │    8   │  87.5%   │  +567 BUX                    │  │
│  │  Win One 3-flip   │   23   │  82.6%   │  +1,234 BUX                  │  │
│  │  Win One 2-flip   │   10   │  70.0%   │  +456 BUX                    │  │
│  │  Single Flip      │   15   │  46.7%   │  +890 BUX                    │  │
│  │  Win All 2-flip   │    5   │  20.0%   │  +345 BUX                    │  │
│  │  Win All 3-flip   │    4   │  25.0%   │  +678 BUX                    │  │
│  │  Win All 4-flip   │    2   │  0.0%    │  -100 BUX                    │  │
│  │  Win All 5-flip   │    0   │  N/A     │  0 BUX                       │  │
│  └───────────────────┴────────┴──────────┴──────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.6 UI Display - Players List Page

**What the UI Shows:**

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Player Stats                                           [Search: ______]   │
│  Showing 50 of 127 players                                                 │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────┬────────┬──────────────┬────────────┬──────────────┬─────┐│
│  │ Wallet      │ Bets   │ BUX Wagered  │ BUX P/L    │ ROGUE Wagered│ ... ││
│  ├─────────────┼────────┼──────────────┼────────────┼──────────────┼─────┤│
│  │ 0xb6b4...37 │ 1,377  │ 10,628       │ -130 ❌    │ 291,109,421  │ →   ││
│  │ 0x14C2...15 │   115  │ 9,191        │ +4,406 ✅  │ 3,614,563    │ →   ││
│  │ 0xABC1...89 │    52  │ 5,000        │ +1,234 ✅  │ 0            │ →   ││
│  │ ...         │        │              │            │              │     ││
│  └─────────────┴────────┴──────────────┴────────────┴──────────────┴─────┘│
│                                                                            │
│  [1] [2] [3] ... [Next →]                                                  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Summary (Post-V7)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ADMIN DASHBOARD                                    │
│                                                                              │
│  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐   │
│  │  Global Stats    │      │  Players List    │      │  Player Detail   │   │
│  │  Page            │      │  Page            │      │  Page            │   │
│  └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘   │
│           │                         │                         │              │
│           ▼                         ▼                         ▼              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     BuxBoosterStats Module (Elixir)                     ││
│  │                                                                         ││
│  │  • get_bux_global_stats()       → BuxBoosterGame.getBuxAccounting()    ││
│  │  • get_rogue_global_stats()     → ROGUEBankroll.buxBoosterAccounting() ││
│  │  • get_bux_player_stats(addr)   → BuxBoosterGame.getBuxPlayerStats()   ││
│  │  • get_rogue_player_stats(addr) → ROGUEBankroll.buxBoosterPlayerStats()││
│  │  • get_house_balances()         → Both contracts                       ││
│  │  • get_all_players()            → Scan BetPlaced events / Mnesia cache ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                    │                             │
│           ▼                                    ▼                             │
│  ┌─────────────────────────┐      ┌─────────────────────────┐               │
│  │  Ethereumex HTTP Client │      │  Mnesia Cache           │               │
│  │  (JSON-RPC calls)       │      │  (player index,         │               │
│  │                         │      │   cached stats)         │               │
│  └───────────┬─────────────┘      └─────────────────────────┘               │
└──────────────┼──────────────────────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                          ROGUE CHAIN (On-Chain)                              │
│                                                                              │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐   │
│  │  BuxBoosterGame Contract        │  │  ROGUEBankroll Contract         │   │
│  │  0x97b6...17B                   │  │  0x51DB...2fd                   │   │
│  │                                 │  │                                 │   │
│  │  V7: BUX-Only Stats ✅          │  │  ROGUE-Only Stats ✅            │   │
│  │  ─────────────────────          │  │  ─────────────────────          │   │
│  │  • buxPlayerStats mapping       │  │  • buxBoosterPlayerStats        │   │
│  │    - totalBets                  │  │    - totalBets                  │   │
│  │    - wins                       │  │    - wins                       │   │
│  │    - losses                     │  │    - losses                     │   │
│  │    - totalWagered               │  │    - totalWagered               │   │
│  │    - totalWinnings              │  │    - totalWinnings              │   │
│  │    - totalLosses                │  │    - totalLosses                │   │
│  │    - betsPerDifficulty[9]       │  │                                 │   │
│  │    - pnlPerDifficulty[9]        │  │  • buxBoosterAccounting         │   │
│  │                                 │  │    - totalBets                  │   │
│  │  • buxAccounting                │  │    - totalWins/Losses           │   │
│  │    - totalBets                  │  │    - totalVolumeWagered         │   │
│  │    - totalWins/Losses           │  │    - totalPayouts               │   │
│  │    - totalVolumeWagered         │  │    - totalHouseProfit           │   │
│  │    - totalPayouts               │  │    - largestWin/Bet             │   │
│  │    - totalHouseProfit           │  │                                 │   │
│  │    - largestWin/Bet             │  │                                 │   │
│  │                                 │  │                                 │   │
│  └─────────────────────────────────┘  └─────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### 3.7 Players List Page

**File**: `lib/blockster_v2_web/live/admin/stats_live/players.ex`

Features:
- Paginated list of all players
- Sortable by: total bets, total wagered, net P/L
- Search by wallet address
- Quick stats for each player

```elixir
defmodule BlocksterV2Web.Admin.StatsLive.Players do
  use BlocksterV2Web, :live_view

  @per_page 50

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(
      players: [],
      page: 1,
      total_pages: 1,
      sort_by: :total_wagered,
      sort_order: :desc,
      search: "",
      loading: true
    )
    |> load_players_async()

    {:ok, socket}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    # Toggle sort order if same field, otherwise default to desc
    socket = socket
    |> assign(sort_by: String.to_atom(field))
    |> load_players_async()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket = socket
    |> assign(search: query, page: 1)
    |> load_players_async()

    {:noreply, socket}
  end

  def handle_event("page", %{"page" => page}, socket) do
    socket = socket
    |> assign(page: String.to_integer(page))
    |> load_players_async()

    {:noreply, socket}
  end

  defp load_players_async(socket) do
    %{page: page, sort_by: sort_by, sort_order: sort_order, search: search} = socket.assigns

    start_async(socket, :load_players, fn ->
      BuxBoosterStats.get_all_player_stats(
        page: page,
        per_page: @per_page,
        sort_by: sort_by,
        sort_order: sort_order,
        search: search
      )
    end)
  end
end
```

**Template**: `lib/blockster_v2_web/live/admin/stats_live/players.html.heex`

```heex
<div class="p-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-haas_medium_65">Player Stats</h1>

    <!-- Search -->
    <form phx-change="search" phx-debounce="300">
      <input
        type="text"
        name="query"
        value={@search}
        placeholder="Search wallet address..."
        class="px-4 py-2 border rounded-lg w-64"
      />
    </form>
  </div>

  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="w-full">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-4 py-3 text-left text-sm font-medium text-gray-500">Wallet</th>
          <th class="px-4 py-3 text-right text-sm font-medium text-gray-500 cursor-pointer" phx-click="sort" phx-value-field="total_bets">
            Total Bets <%= sort_indicator(@sort_by, @sort_order, :total_bets) %>
          </th>
          <th class="px-4 py-3 text-right text-sm font-medium text-gray-500 cursor-pointer" phx-click="sort" phx-value-field="bux_wagered">
            BUX Wagered <%= sort_indicator(@sort_by, @sort_order, :bux_wagered) %>
          </th>
          <th class="px-4 py-3 text-right text-sm font-medium text-gray-500 cursor-pointer" phx-click="sort" phx-value-field="bux_pnl">
            BUX P/L <%= sort_indicator(@sort_by, @sort_order, :bux_pnl) %>
          </th>
          <th class="px-4 py-3 text-right text-sm font-medium text-gray-500 cursor-pointer" phx-click="sort" phx-value-field="rogue_wagered">
            ROGUE Wagered <%= sort_indicator(@sort_by, @sort_order, :rogue_wagered) %>
          </th>
          <th class="px-4 py-3 text-right text-sm font-medium text-gray-500 cursor-pointer" phx-click="sort" phx-value-field="rogue_pnl">
            ROGUE P/L <%= sort_indicator(@sort_by, @sort_order, :rogue_pnl) %>
          </th>
          <th class="px-4 py-3"></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200">
        <%= for player <- @players do %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3">
              <a href={"https://roguescan.io/address/#{player.wallet}"} target="_blank" class="text-blue-600 hover:underline font-mono text-sm">
                <%= String.slice(player.wallet, 0..5) %>...<%= String.slice(player.wallet, -4..-1) %>
              </a>
            </td>
            <td class="px-4 py-3 text-right"><%= player.total_bets %></td>
            <td class="px-4 py-3 text-right"><%= format_number(player.bux_wagered) %></td>
            <td class={"px-4 py-3 text-right #{pnl_color(player.bux_pnl)}"}><%= format_pnl(player.bux_pnl) %></td>
            <td class="px-4 py-3 text-right"><%= format_number(player.rogue_wagered) %></td>
            <td class={"px-4 py-3 text-right #{pnl_color(player.rogue_pnl)}"}><%= format_pnl(player.rogue_pnl) %></td>
            <td class="px-4 py-3">
              <.link navigate={~p"/admin/stats/players/#{player.wallet}"} class="text-blue-600 hover:underline">
                Details →
              </.link>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <!-- Pagination -->
  <div class="mt-4 flex justify-center gap-2">
    <%= for page <- 1..@total_pages do %>
      <button
        phx-click="page"
        phx-value-page={page}
        class={"px-3 py-1 rounded #{if page == @page, do: "bg-blue-600 text-white", else: "bg-gray-200"}"}
      >
        <%= page %>
      </button>
    <% end %>
  </div>
</div>
```

### 3.4 Player Detail Page

**File**: `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex`

Shows comprehensive stats for a single player:
- BUX stats (calculated)
- ROGUE stats (direct)
- Per-difficulty breakdown (combined only, with caveat note)
- Recent bets history (from Mnesia if available)
- Link to Roguescan

```elixir
defmodule BlocksterV2Web.Admin.StatsLive.PlayerDetail do
  use BlocksterV2Web, :live_view

  def mount(%{"address" => address}, _session, socket) do
    socket = socket
    |> assign(wallet: address, stats: nil, loading: true)
    |> start_async(:load_stats, fn ->
      BuxBoosterStats.get_player_stats(address)
    end)

    {:ok, socket}
  end
end
```

## Phase 4: Admin Authentication

### 4.1 Admin Role Check

Add admin check to user schema or use a simple allowlist:

```elixir
# In lib/blockster_v2/accounts.ex
def is_admin?(user) do
  user.email in Application.get_env(:blockster_v2, :admin_emails, [])
end

# Or check a role field
def is_admin?(user) do
  user.role == :admin
end
```

### 4.2 Admin Pipeline

```elixir
# In router.ex
pipeline :require_admin do
  plug :require_authenticated_user
  plug :require_admin_role
end

defp require_admin_role(conn, _opts) do
  if Accounts.is_admin?(conn.assigns.current_user) do
    conn
  else
    conn
    |> put_flash(:error, "You don't have access to this area")
    |> redirect(to: ~p"/")
    |> halt()
  end
end
```

## Phase 5: Implementation Order

### Step 1: Dependencies & Config (Day 1)
- [ ] Configure RPC URL in config (Req library already available)
- [ ] Add admin emails to config

### Step 2: Stats Module (Day 1-2)
- [ ] Create `BuxBoosterStats` module
- [ ] Implement ROGUE stats queries
- [ ] Implement combined stats queries
- [ ] Implement BUX calculation logic
- [ ] Add unit tests

### Step 3: Player Indexing (Day 2)
- [ ] Create Mnesia table for players
- [ ] Implement event scanning for player discovery
- [ ] Create background job for periodic indexing

### Step 4: Caching Layer (Day 2-3)
- [ ] Create `BuxBoosterStats.Cache` GenServer
- [ ] Cache global stats (5 min TTL)
- [ ] Cache player stats (1 min TTL)
- [ ] Add cache invalidation on demand

### Step 5: Admin Routes & Auth (Day 3)
- [ ] Add admin routes to router
- [ ] Implement admin authentication pipeline
- [ ] Configure admin allowlist

### Step 6: Global Stats Page (Day 3-4)
- [ ] Create Index LiveView
- [ ] Design stats cards UI
- [ ] Add house balance display
- [ ] Add refresh button

### Step 7: Players List Page (Day 4-5)
- [ ] Create Players LiveView
- [ ] Implement pagination
- [ ] Implement sorting
- [ ] Implement search
- [ ] Design responsive table

### Step 8: Player Detail Page (Day 5)
- [ ] Create PlayerDetail LiveView
- [ ] Display separated BUX/ROGUE stats
- [ ] Show per-difficulty breakdown (with caveat)
- [ ] Add recent bets from Mnesia
- [ ] Add external links (Roguescan)

### Step 9: Testing & Polish (Day 6)
- [ ] Test with real data
- [ ] Handle edge cases (new players, zero stats)
- [ ] Add loading states
- [ ] Add error handling
- [ ] Mobile responsiveness

## File Structure

```
lib/blockster_v2/
├── bux_booster_stats.ex              # Main stats module
├── bux_booster_stats/
│   ├── cache.ex                      # Caching GenServer
│   ├── player_index.ex               # Player discovery from events
│   └── contract_queries.ex           # Raw contract interaction

lib/blockster_v2_web/
├── live/admin/
│   └── stats_live/
│       ├── index.ex                  # Global stats page
│       ├── index.html.heex
│       ├── players.ex                # Players list page
│       ├── players.html.heex
│       ├── player_detail.ex          # Single player detail
│       └── player_detail.html.heex
```

## API Endpoints (Optional)

If external access is needed, add JSON API:

```elixir
# In router.ex
scope "/api/admin", BlocksterV2Web.API.Admin do
  pipe_through [:api, :require_admin_api_key]

  get "/stats/global", StatsController, :global
  get "/stats/players", StatsController, :players
  get "/stats/players/:address", StatsController, :player
end
```

## Future Enhancements

1. **Charts & Graphs**: Add volume over time, P/L trends using Chart.js
2. **Export**: CSV export of player stats
3. **Alerts**: Notify on large bets or unusual activity
4. **Real-time Updates**: LiveView subscriptions for live bet tracking
5. **Per-Token Difficulty Stats**: Would require contract upgrade to separate BUX/ROGUE in per-difficulty arrays

---

# Contract Upgrade: Separate BUX and ROGUE Stats

## The Problem

The current architecture has a fundamental design flaw: **BuxBoosterGame stores combined BUX+ROGUE stats in a single `playerStats` mapping**.

This causes several issues:

1. **No direct BUX stats query** - Must calculate by subtracting ROGUE from combined
2. **No BUX global accounting** - Only ROGUE has `buxBoosterAccounting`
3. **Per-difficulty breakdown is combined** - Cannot see BUX vs ROGUE performance per difficulty
4. **Inconsistent data structures** - ROGUE has wins/losses counts, BUX side doesn't
5. **Complexity for consumers** - Any dashboard/API must do math to separate stats

## Root Cause

Both settlement functions write to the same mapping:

```solidity
// BUX settlement (ERC-20)
function _processSettlement(Bet storage bet, ...) internal {
    PlayerStats storage stats = playerStats[bet.player];  // <-- Same mapping
    stats.totalBets++;
    // ...
}

// ROGUE settlement (native token)
function _processSettlementROGUE(Bet storage bet, ...) internal {
    PlayerStats storage stats = playerStats[bet.player];  // <-- Same mapping
    stats.totalBets++;
    // ...
}
```

## Solution: Contract V7 Upgrade

Upgrade BuxBoosterGame to store BUX and ROGUE stats separately.

**Note:** V6 was the referral system upgrade. This separated stats feature would be V7.

### New Storage Layout

```solidity
// ============ V7: Separated Stats ============

// BUX-specific player stats
struct BuxPlayerStats {
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 totalWagered;
    uint256 totalWinnings;    // Profit from wins
    uint256 totalLosses;      // Amount lost
    uint256[9] betsPerDifficulty;
    int256[9] profitLossPerDifficulty;
}

// BUX global accounting (mirrors ROGUE's buxBoosterAccounting)
struct BuxAccounting {
    uint256 totalBets;
    uint256 totalWins;
    uint256 totalLosses;
    uint256 totalVolumeWagered;
    uint256 totalPayouts;
    int256 totalHouseProfit;
    uint256 largestWin;
    uint256 largestBet;
}

// IMPORTANT: Existing storage variables remain unchanged (UUPS proxy compatibility)
// The old playerStats mapping stays in place - we just stop writing to it

// New mappings added at END of storage (V7)
mapping(address => BuxPlayerStats) public buxPlayerStats;
BuxAccounting public buxAccounting;
```

### Updated Settlement Functions

```solidity
function _processSettlement(Bet storage bet, uint8 diffIndex, bool won) internal returns (uint256 payout) {
    TokenConfig storage config = tokenConfigs[bet.token];

    // V7: Write to BUX-specific stats (stop writing to old playerStats)
    BuxPlayerStats storage stats = buxPlayerStats[bet.player];

    stats.totalBets++;
    stats.totalWagered += bet.amount;
    stats.betsPerDifficulty[diffIndex]++;

    // Update global BUX accounting
    buxAccounting.totalBets++;
    buxAccounting.totalVolumeWagered += bet.amount;

    if (bet.amount > buxAccounting.largestBet) {
        buxAccounting.largestBet = bet.amount;
    }

    if (won) {
        payout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;
        bet.status = BetStatus.Won;
        config.houseBalance -= (payout - bet.amount);

        int256 profit = int256(payout) - int256(bet.amount);
        stats.wins++;
        stats.totalWinnings += uint256(profit);
        stats.profitLossPerDifficulty[diffIndex] += profit;

        // Global accounting
        buxAccounting.totalWins++;
        buxAccounting.totalPayouts += payout;
        buxAccounting.totalHouseProfit -= profit;

        if (payout > buxAccounting.largestWin) {
            buxAccounting.largestWin = payout;
        }

        IERC20(bet.token).safeTransfer(bet.player, payout);
    } else {
        payout = 0;
        bet.status = BetStatus.Lost;
        config.houseBalance += bet.amount;

        stats.losses++;
        stats.totalLosses += bet.amount;
        stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);

        // Global accounting
        buxAccounting.totalLosses++;
        buxAccounting.totalHouseProfit += int256(bet.amount);
    }
}
```

### New View Functions

```solidity
/// @notice Get BUX-specific stats for a player (V7)
function getBuxPlayerStats(address player) external view returns (
    uint256 totalBets,
    uint256 wins,
    uint256 losses,
    uint256 totalWagered,
    uint256 totalWinnings,
    uint256 totalLosses,
    uint256[9] memory betsPerDifficulty,
    int256[9] memory profitLossPerDifficulty
) {
    BuxPlayerStats storage stats = buxPlayerStats[player];
    return (
        stats.totalBets,
        stats.wins,
        stats.losses,
        stats.totalWagered,
        stats.totalWinnings,
        stats.totalLosses,
        stats.betsPerDifficulty,
        stats.profitLossPerDifficulty
    );
}

/// @notice Get BUX global accounting (V7)
function getBuxAccounting() external view returns (
    uint256 totalBets,
    uint256 totalWins,
    uint256 totalLosses,
    uint256 totalVolumeWagered,
    uint256 totalPayouts,
    int256 totalHouseProfit,
    uint256 largestWin,
    uint256 largestBet
) {
    return (
        buxAccounting.totalBets,
        buxAccounting.totalWins,
        buxAccounting.totalLosses,
        buxAccounting.totalVolumeWagered,
        buxAccounting.totalPayouts,
        buxAccounting.totalHouseProfit,
        buxAccounting.largestWin,
        buxAccounting.largestBet
    );
}

/// @notice Get combined stats for backwards compatibility (deprecated)
/// @dev Returns old playerStats mapping data, will not include new bets after V7
/// @dev Old mapping preserved - NOT removed (UUPS storage layout rules)
function getPlayerStats(address player) external view returns (...) {
    // Keep for backwards compatibility but mark as deprecated
    // This mapping is no longer written to after V7, only read for historical data
    PlayerStats storage stats = playerStats[player];
    return (...);
}
```

### Migration Considerations

#### Option A: Clean Slate (Recommended)

Start fresh with V7 stats. Old stats remain in deprecated mappings for historical reference.

**Pros:**
- Simple upgrade
- No data migration needed
- Clean separation going forward

**Cons:**
- Historical BUX-only stats not available (they were never accurately tracked anyway)
- Stats reset to zero for new mappings

**Implementation:**
```solidity
function initializeV7() external reinitializer(7) {
    // No migration needed - new mappings start at zero
    // Old playerStats mapping preserved (NOT removed) for historical reference
}
```

#### Option B: Backfill from Events

Scan historical `BetSettled` events and reconstruct BUX-only stats.

**Pros:**
- Historical accuracy

**Cons:**
- Complex migration
- Gas intensive if done on-chain
- Better done off-chain then written via admin function

**Implementation:**
```solidity
/// @notice Admin function to backfill historical BUX stats (one-time migration)
/// @dev Called with data computed off-chain from BetSettled events
function backfillBuxStats(
    address[] calldata players,
    BuxPlayerStats[] calldata stats
) external onlyOwner {
    require(players.length == stats.length, "Length mismatch");
    for (uint i = 0; i < players.length; i++) {
        buxPlayerStats[players[i]] = stats[i];
    }
}

function backfillBuxAccounting(BuxAccounting calldata accounting) external onlyOwner {
    buxAccounting = accounting;
}
```

### ROGUE Stats - No Changes Needed

ROGUE stats are already properly separated in ROGUEBankroll:
- `buxBoosterPlayerStats` - per-player ROGUE stats
- `buxBoosterAccounting` - global ROGUE stats

No changes needed to ROGUEBankroll contract.

### Post-Upgrade Query Pattern

After V7, querying becomes simple and consistent:

```javascript
// BUX Stats (direct query - no calculation needed!)
const buxPlayerStats = await buxBoosterGame.getBuxPlayerStats(playerAddress);
const buxGlobalStats = await buxBoosterGame.getBuxAccounting();

// ROGUE Stats (unchanged)
const roguePlayerStats = await rogueBankroll.buxBoosterPlayerStats(playerAddress);
const rogueGlobalStats = await rogueBankroll.buxBoosterAccounting();
```

### Updated ABI Reference

```javascript
const BUX_BOOSTER_V7_ABI = [
  // V7: BUX-specific stats
  "function getBuxPlayerStats(address player) external view returns (uint256 totalBets, uint256 wins, uint256 losses, uint256 totalWagered, uint256 totalWinnings, uint256 totalLosses, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)",
  "function getBuxAccounting() external view returns (uint256 totalBets, uint256 totalWins, uint256 totalLosses, uint256 totalVolumeWagered, uint256 totalPayouts, int256 totalHouseProfit, uint256 largestWin, uint256 largestBet)",

  // Deprecated (V1-V6 combined stats) - still readable for historical data
  "function getPlayerStats(address player) external view returns (uint256 totalBets, uint256 totalStaked, int256 overallProfitLoss, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)"
];
```

## Upgrade Checklist

### Pre-Upgrade
- [ ] Write V7 contract changes (add new storage at END, do not remove anything)
- [ ] Add comprehensive tests for new stats tracking
- [ ] Test upgrade on testnet
- [ ] Decide on migration strategy (clean slate vs backfill)
- [ ] If backfilling, prepare off-chain script to compute historical BUX stats from events

### Upgrade Process
- [ ] Deploy new implementation
- [ ] Upgrade proxy via `upgradeToAndCall()`
- [ ] Call `initializeV7()`
- [ ] If backfilling, call `backfillBuxStats()` and `backfillBuxAccounting()`
- [ ] Verify new functions work correctly

### Post-Upgrade
- [ ] Update BUX Minter service ABIs
- [ ] Update Phoenix app `BuxBoosterStats` module
- [ ] Update admin dashboard queries
- [ ] Deprecate calculation-based BUX stats code
- [ ] Update this documentation

## Summary

| Stat | Current (V6) | After V7 |
|------|--------------|----------|
| BUX player stats | Calculate: combined - ROGUE | Direct: `getBuxPlayerStats()` |
| BUX global stats | Not available | Direct: `getBuxAccounting()` |
| BUX per-difficulty | Combined with ROGUE | Separate: in `BuxPlayerStats` |
| ROGUE player stats | Direct: `buxBoosterPlayerStats()` | No change |
| ROGUE global stats | Direct: `buxBoosterAccounting()` | No change |

The V7 upgrade provides:
1. **Direct BUX queries** - No more calculation needed
2. **BUX global accounting** - Matches ROGUE's structure
3. **Separated per-difficulty stats** - Can analyze BUX and ROGUE performance independently
4. **Consistent data structures** - Both currencies have same stat fields
5. **Simpler consumer code** - Dashboard/API just queries, no math required

---

# Implementation Checklist

This is a comprehensive task list for implementing the BuxBooster admin stats system. Tasks are organized by phase with dependencies noted.

## Phase 0: Contract V7 Upgrade (Required First)

### 0.1 Contract Development
- [ ] **0.1.1** Update `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` with:
  - [ ] Add `BuxPlayerStats` struct (totalBets, wins, losses, totalWagered, totalWinnings, totalLosses, betsPerDifficulty[9], profitLossPerDifficulty[9])
  - [ ] Add `BuxAccounting` struct (mirrors ROGUEBankroll's buxBoosterAccounting)
  - [ ] Add `mapping(address => BuxPlayerStats) public buxPlayerStats` at END of storage
  - [ ] Add `BuxAccounting public buxAccounting` at END of storage
  - [ ] **CRITICAL**: Do NOT remove any existing storage variables
  - [ ] **CRITICAL**: Add new variables ONLY at the END of storage layout
- [ ] **0.1.2** Update `_processSettlement()` to write to new `buxPlayerStats` mapping
- [ ] **0.1.3** Update `_processSettlement()` to update `buxAccounting` global stats
- [ ] **0.1.4** Add `getBuxPlayerStats(address)` view function
- [ ] **0.1.5** Add `getBuxAccounting()` view function
- [ ] **0.1.6** Add `initializeV7()` reinitializer function
- [ ] **0.1.7** (Optional) Add `backfillBuxStats()` admin function for historical data migration
- [ ] **0.1.8** (Optional) Add `backfillBuxAccounting()` admin function

### 0.2 Contract Testing
- [ ] **0.2.1** Write unit tests for new BUX stats tracking
- [ ] **0.2.2** Write unit tests for new BUX accounting
- [ ] **0.2.3** Test storage layout compatibility (no slot collisions)
- [ ] **0.2.4** Test upgrade from V6 → V7 on local hardhat
- [ ] **0.2.5** Deploy to testnet and verify upgrade works
- [ ] **0.2.6** Test all existing functionality still works after upgrade

### 0.3 Contract Deployment
- [ ] **0.3.1** Compile V7 contract: `npx hardhat compile`
- [ ] **0.3.2** Run force-import if needed: `npx hardhat run scripts/force-import.js --network rogueMainnet`
- [ ] **0.3.3** Deploy new implementation: `npx hardhat run scripts/upgrade-manual.js --network rogueMainnet`
- [ ] **0.3.4** Call `initializeV7()`: create and run `scripts/init-v7.js`
- [ ] **0.3.5** Verify upgrade: `npx hardhat run scripts/verify-upgrade.js --network rogueMainnet`
- [ ] **0.3.6** Update `CLAUDE.md` with new implementation address
- [ ] **0.3.7** (Optional) Run backfill scripts if migrating historical data

### 0.4 Service Updates
- [ ] **0.4.1** Update `bux-minter/index.js` with V7 ABI (add `getBuxPlayerStats`, `getBuxAccounting`)
- [ ] **0.4.2** Redeploy BUX Minter: `cd bux-minter && flyctl deploy`
- [ ] **0.4.3** Verify BUX Minter can query new functions

---

## Phase 1: Backend - Stats Module

### 1.1 Dependencies & Config
- [ ] **1.1.1** No new dependencies needed - `Req` library is already available in the project
- [ ] **1.1.2** Add RPC URL to `config/config.exs`:
  ```elixir
  config :blockster_v2, :rogue_chain_rpc,
    url: "https://rpc.roguechain.io/rpc"
  ```
- [ ] **1.1.3** Add admin emails to `config/config.exs`:
  ```elixir
  config :blockster_v2, :admin_emails, ["admin@example.com"]
  ```
- [ ] **1.1.4** Add contract addresses to config:
  ```elixir
  config :blockster_v2, :contracts,
    bux_booster_game: "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B",
    rogue_bankroll: "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  ```

### 1.2 Core Stats Module
- [ ] **1.2.1** Create `lib/blockster_v2/bux_booster_stats.ex` with module doc
- [ ] **1.2.2** Implement `get_bux_global_stats/0` - calls `getBuxAccounting()`
- [ ] **1.2.3** Implement `get_rogue_global_stats/0` - calls `buxBoosterAccounting()`
- [ ] **1.2.4** Implement `get_bux_player_stats/1` - calls `getBuxPlayerStats(address)`
- [ ] **1.2.5** Implement `get_rogue_player_stats/1` - calls `buxBoosterPlayerStats(address)`
- [ ] **1.2.6** Implement `get_player_stats/1` - returns both BUX and ROGUE stats
- [ ] **1.2.7** Implement `get_house_balances/0` - queries both contracts
- [ ] **1.2.8** Add ABI encoding/decoding helper functions
- [ ] **1.2.9** Add error handling for RPC failures

### 1.3 Contract Queries Module
- [ ] **1.3.1** Create `lib/blockster_v2/bux_booster_stats/contract_queries.ex`
- [ ] **1.3.2** Implement `call_contract/3` - raw eth_call wrapper
- [ ] **1.3.3** Implement `encode_function_call/2` - ABI encoding
- [ ] **1.3.4** Implement `decode_response/2` - ABI decoding
- [ ] **1.3.5** Add function selectors for all query functions
- [ ] **1.3.6** Add HTTP timeout configuration (10 seconds)

### 1.4 Unit Tests
- [ ] **1.4.1** Create `test/blockster_v2/bux_booster_stats_test.exs`
- [ ] **1.4.2** Test ABI encoding functions
- [ ] **1.4.3** Test ABI decoding functions
- [ ] **1.4.4** Test with mock RPC responses
- [ ] **1.4.5** Test error handling

---

## Phase 2: Backend - Player Discovery

### 2.1 Mnesia Table
- [ ] **2.1.1** Add `:bux_booster_players` table to `MnesiaInitializer`:
  ```elixir
  :mnesia.create_table(:bux_booster_players, [
    attributes: [:wallet_address, :first_bet_block, :last_bet_block, :total_bets_indexed],
    disc_copies: [node()],
    type: :set,
    index: [:last_bet_block]
  ])
  ```
- [ ] **2.1.2** Restart both nodes to create new table
- [ ] **2.1.3** Verify table created: `:mnesia.table_info(:bux_booster_players, :size)`

### 2.2 Player Index Module
- [ ] **2.2.1** Create `lib/blockster_v2/bux_booster_stats/player_index.ex`
- [ ] **2.2.2** Implement `index_players_from_events/1` - scans BetPlaced events
- [ ] **2.2.3** Implement `get_all_player_addresses/0` - returns list from Mnesia
- [ ] **2.2.4** Implement `get_player_count/0` - returns count
- [ ] **2.2.5** Implement `add_player/1` - adds single player to index
- [ ] **2.2.6** Implement `get_last_indexed_block/0` - for incremental indexing
- [ ] **2.2.7** Add event log parsing for BetPlaced events

### 2.3 Background Indexer
- [ ] **2.3.1** Create `lib/blockster_v2/bux_booster_stats/indexer.ex` GenServer
- [ ] **2.3.2** Schedule periodic indexing (every 5 minutes)
- [ ] **2.3.3** Implement incremental indexing (from last block)
- [ ] **2.3.4** Add to supervision tree in `application.ex`
- [ ] **2.3.5** Use GlobalSingleton for cluster-wide single instance
- [ ] **2.3.6** Add logging for indexing progress

---

## Phase 3: Backend - Caching Layer

### 3.1 Cache GenServer
- [ ] **3.1.1** Create `lib/blockster_v2/bux_booster_stats/cache.ex`
- [ ] **3.1.2** Create ETS table for stats cache
- [ ] **3.1.3** Implement `get_global_stats/0` - returns cached or fetches
- [ ] **3.1.4** Implement `get_player_stats/1` - returns cached or fetches
- [ ] **3.1.5** Implement `invalidate_global/0` - clears global cache
- [ ] **3.1.6** Implement `invalidate_player/1` - clears player cache
- [ ] **3.1.7** Add TTL: 5 minutes for global, 1 minute for player stats
- [ ] **3.1.8** Add to supervision tree
- [ ] **3.1.9** Add cache hit/miss logging (debug level)

---

## Phase 4: Admin Authentication

### 4.1 Admin Check Functions
- [ ] **4.1.1** Add `is_admin?/1` function to `lib/blockster_v2/accounts.ex`
- [ ] **4.1.2** Check against configured admin emails list
- [ ] **4.1.3** Add unit test for admin check

### 4.2 Router Pipeline
- [ ] **4.2.1** Add `:require_admin` pipeline to `router.ex`
- [ ] **4.2.2** Implement `require_admin_role/2` plug
- [ ] **4.2.3** Add flash message for unauthorized access
- [ ] **4.2.4** Redirect non-admins to home page

### 4.3 Admin Routes
- [ ] **4.3.1** Add admin scope to `router.ex`:
  ```elixir
  scope "/admin", BlocksterV2Web.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]
    live "/stats", StatsLive.Index, :index
    live "/stats/players", StatsLive.Players, :index
    live "/stats/players/:address", StatsLive.PlayerDetail, :show
  end
  ```

---

## Phase 5: Global Stats Page

### 5.1 LiveView Module
- [ ] **5.1.1** Create directory `lib/blockster_v2_web/live/admin/stats_live/`
- [ ] **5.1.2** Create `lib/blockster_v2_web/live/admin/stats_live/index.ex`
- [ ] **5.1.3** Implement `mount/3` with loading state
- [ ] **5.1.4** Implement `handle_info(:load_stats, socket)` with async fetch
- [ ] **5.1.5** Implement `handle_async/3` for BUX global stats
- [ ] **5.1.6** Implement `handle_async/3` for ROGUE global stats
- [ ] **5.1.7** Implement `handle_async/3` for house balances
- [ ] **5.1.8** Implement `handle_event("refresh", ...)` for manual refresh
- [ ] **5.1.9** Add `format_bux/1` helper (divide by 10^18, format with commas)
- [ ] **5.1.10** Add `format_rogue/1` helper (divide by 10^18, format with commas)

### 5.2 Template
- [ ] **5.2.1** Create `lib/blockster_v2_web/live/admin/stats_live/index.html.heex`
- [ ] **5.2.2** Add header with title and refresh button
- [ ] **5.2.3** Add "last updated" timestamp display
- [ ] **5.2.4** Create BUX stats card (blue theme)
- [ ] **5.2.5** Create ROGUE stats card (yellow theme)
- [ ] **5.2.6** Add loading skeleton states
- [ ] **5.2.7** Add house balances section
- [ ] **5.2.8** Style profit/loss with green/red colors
- [ ] **5.2.9** Add responsive grid layout (1 col mobile, 2 col desktop)

---

## Phase 6: Players List Page

### 6.1 LiveView Module
- [ ] **6.1.1** Create `lib/blockster_v2_web/live/admin/stats_live/players.ex`
- [ ] **6.1.2** Implement `mount/3` with pagination state
- [ ] **6.1.3** Implement `load_players_async/1` helper
- [ ] **6.1.4** Implement `handle_event("sort", ...)` for column sorting
- [ ] **6.1.5** Implement `handle_event("search", ...)` for wallet search
- [ ] **6.1.6** Implement `handle_event("page", ...)` for pagination
- [ ] **6.1.7** Implement `handle_async(:load_players, ...)` handler
- [ ] **6.1.8** Add debounced search (300ms)

### 6.2 Stats Module Updates
- [ ] **6.2.1** Add `get_all_player_stats/1` to `BuxBoosterStats` module
- [ ] **6.2.2** Accept options: page, per_page, sort_by, sort_order, search
- [ ] **6.2.3** Implement pagination logic
- [ ] **6.2.4** Implement sorting logic
- [ ] **6.2.5** Implement wallet address search filter

### 6.3 Template
- [ ] **6.3.1** Create `lib/blockster_v2_web/live/admin/stats_live/players.html.heex`
- [ ] **6.3.2** Add header with search input
- [ ] **6.3.3** Create sortable table headers
- [ ] **6.3.4** Add columns: Wallet, Total Bets, BUX Wagered, BUX P/L, ROGUE Wagered, ROGUE P/L
- [ ] **6.3.5** Add sort indicator arrows
- [ ] **6.3.6** Add pagination controls
- [ ] **6.3.7** Add "Details →" link for each row
- [ ] **6.3.8** Style P/L with green/red colors
- [ ] **6.3.9** Add loading state for table
- [ ] **6.3.10** Add Roguescan links for wallet addresses

---

## Phase 7: Player Detail Page

### 7.1 LiveView Module
- [ ] **7.1.1** Create `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex`
- [ ] **7.1.2** Implement `mount/3` - extract address from params
- [ ] **7.1.3** Implement async stats loading
- [ ] **7.1.4** Implement `handle_async/3` for player stats
- [ ] **7.1.5** Add helper to format difficulty level names

### 7.2 Template
- [ ] **7.2.1** Create `lib/blockster_v2_web/live/admin/stats_live/player_detail.html.heex`
- [ ] **7.2.2** Add header with wallet address and Roguescan link
- [ ] **7.2.3** Create BUX stats card with all fields
- [ ] **7.2.4** Create ROGUE stats card with all fields
- [ ] **7.2.5** Create per-difficulty breakdown table (BUX)
- [ ] **7.2.6** Add difficulty level names mapping
- [ ] **7.2.7** Calculate and display win rate per difficulty
- [ ] **7.2.8** Style P/L with green/red colors
- [ ] **7.2.9** Add loading skeleton state
- [ ] **7.2.10** Add "Back to Players" navigation

---

## Phase 8: Testing & Polish

### 8.1 Integration Testing
- [ ] **8.1.1** Test global stats page loads correctly
- [ ] **8.1.2** Test players list pagination works
- [ ] **8.1.3** Test players list sorting works
- [ ] **8.1.4** Test players list search works
- [ ] **8.1.5** Test player detail page loads for valid address
- [ ] **8.1.6** Test player detail page handles invalid address
- [ ] **8.1.7** Test admin authentication blocks non-admins
- [ ] **8.1.8** Test refresh button updates stats

### 8.2 Edge Cases
- [ ] **8.2.1** Handle player with zero bets
- [ ] **8.2.2** Handle player with only BUX bets (no ROGUE)
- [ ] **8.2.3** Handle player with only ROGUE bets (no BUX)
- [ ] **8.2.4** Handle RPC timeout gracefully
- [ ] **8.2.5** Handle RPC error gracefully
- [ ] **8.2.6** Handle empty players list

### 8.3 UI Polish
- [ ] **8.3.1** Add loading spinners to all async operations
- [ ] **8.3.2** Add error messages for failed loads
- [ ] **8.3.3** Ensure mobile responsiveness on all pages
- [ ] **8.3.4** Add hover states to table rows
- [ ] **8.3.5** Add cursor-pointer to all clickable elements
- [ ] **8.3.6** Use consistent number formatting throughout
- [ ] **8.3.7** Add tooltips for abbreviations if needed

### 8.4 Documentation
- [ ] **8.4.1** Update `CLAUDE.md` with new admin routes
- [ ] **8.4.2** Update `CLAUDE.md` with V7 contract details
- [ ] **8.4.3** Document admin access requirements
- [ ] **8.4.4** Add inline code comments where helpful

---

## Phase 9: Deployment

### 9.1 Pre-Deploy Checklist
- [ ] **9.1.1** Ensure V7 contract is deployed and verified
- [ ] **9.1.2** Ensure BUX Minter is updated with V7 ABI
- [ ] **9.1.3** Run full test suite locally
- [ ] **9.1.4** Test on staging if available
- [ ] **9.1.5** Add admin emails to production config/secrets

### 9.2 Deploy
- [ ] **9.2.1** Commit all changes
- [ ] **9.2.2** Push to branch
- [ ] **9.2.3** Create PR if required
- [ ] **9.2.4** Deploy to Fly.io: `flyctl deploy --app blockster-v2`
- [ ] **9.2.5** Verify deployment successful
- [ ] **9.2.6** Test admin pages in production

### 9.3 Post-Deploy
- [ ] **9.3.1** Monitor logs for errors
- [ ] **9.3.2** Verify stats match on-chain data
- [ ] **9.3.3** Run player indexer initial scan
- [ ] **9.3.4** Verify cache is working (check response times)

---

## Summary Metrics

| Phase | Tasks | Estimated Effort |
|-------|-------|------------------|
| 0. Contract V7 | 29 tasks | 2-3 days |
| 1. Stats Module | 24 tasks | 1-2 days |
| 2. Player Discovery | 16 tasks | 1 day |
| 3. Caching | 9 tasks | 0.5 days |
| 4. Admin Auth | 8 tasks | 0.5 days |
| 5. Global Stats Page | 19 tasks | 1 day |
| 6. Players List | 23 tasks | 1 day |
| 7. Player Detail | 15 tasks | 0.5 days |
| 8. Testing & Polish | 25 tasks | 1 day |
| 9. Deployment | 15 tasks | 0.5 days |
| **TOTAL** | **183 tasks** | **9-11 days** |

---

## Dependencies Graph

```
Phase 0 (Contract V7)
    │
    ├──► Phase 1 (Stats Module) ──► Phase 3 (Caching)
    │         │                          │
    │         ▼                          │
    │    Phase 2 (Player Discovery) ─────┤
    │                                    │
    │                                    ▼
    └──► Phase 4 (Admin Auth) ──► Phase 5 (Global Stats)
                                        │
                                        ▼
                                  Phase 6 (Players List)
                                        │
                                        ▼
                                  Phase 7 (Player Detail)
                                        │
                                        ▼
                                  Phase 8 (Testing)
                                        │
                                        ▼
                                  Phase 9 (Deployment)
```

**Critical Path**: Phase 0 → Phase 1 → Phase 5 → Phase 6 → Phase 7 → Phase 8 → Phase 9

**Parallel Work Possible**:
- Phase 2 and Phase 3 can be done in parallel after Phase 1
- Phase 4 can be done in parallel with Phase 1-3
