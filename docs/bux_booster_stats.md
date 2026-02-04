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

## Phase 0: Contract V7 Upgrade ✅ COMPLETE (Feb 3, 2026)

### Deployment Summary
- **New Implementation**: `0xB6752CB0b1ba55a8AE03F2b4Ad84C854Be629dF0`
- **Upgrade TX**: `0xcf22fd3edc565215b80b0ba501bf6fe0ed9cc09d5e96d43416519473d11249b8`
- **InitializeV7 TX**: `0x3f3fa3e5ee145ec8df515c5b911398fcc4f267c9d05cc3c6ff124b7d84d0d943`
- **Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (unchanged)

### 0.1 Contract Development ✅
- [x] **0.1.1** Update `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` with:
  - [x] Add `BuxPlayerStats` struct (totalBets, wins, losses, totalWagered, totalWinnings, totalLosses, betsPerDifficulty[9], profitLossPerDifficulty[9])
  - [x] Add `BuxAccounting` struct (mirrors ROGUEBankroll's buxBoosterAccounting)
  - [x] Add `mapping(address => BuxPlayerStats) public buxPlayerStats` at END of storage (after `referralAdmin`)
  - [x] Add `BuxAccounting public buxAccounting` at END of storage
  - [x] **CRITICAL**: Did NOT remove any existing storage variables
  - [x] **CRITICAL**: Added new variables ONLY at the END of storage layout
- [x] **0.1.2** Update `_processSettlement()` to write to new `buxPlayerStats` mapping (ONLY writes to new stats, stopped writing to combined `playerStats`)
- [x] **0.1.3** Update `_processSettlement()` to update `buxAccounting` global stats
- [x] **0.1.4** Add `getBuxPlayerStats(address)` view function
- [x] **0.1.5** Add `getBuxAccounting()` view function
- [x] **0.1.6** Add `initializeV7()` reinitializer function
- [ ] **0.1.7** (Skipped) `backfillBuxStats()` - Historical data not migrated, stats start fresh
- [ ] **0.1.8** (Skipped) `backfillBuxAccounting()` - Historical data not migrated, stats start fresh

### 0.2 Contract Testing ✅
- [x] **0.2.1** Write unit tests for new BUX stats tracking - `test/BuxBoosterGame.v7.test.js`
- [x] **0.2.2** Write unit tests for new BUX accounting - 12 tests all passing
- [x] **0.2.3** Test storage layout compatibility (no slot collisions)
- [x] **0.2.4** Test upgrade from V6 → V7 on local hardhat
- [ ] **0.2.5** (Skipped) Deploy to testnet - went directly to mainnet
- [x] **0.2.6** Test all existing functionality still works after upgrade

### 0.3 Contract Deployment ✅
- [x] **0.3.1** Compile V7 contract: `npx hardhat compile`
- [x] **0.3.2** (Not needed) force-import was not required
- [x] **0.3.3** Deploy new implementation via `scripts/upgrade-to-v7.js`
- [x] **0.3.4** Call `initializeV7()` - included in upgrade script
- [x] **0.3.5** Verify upgrade - script verified `getBuxAccounting()` and `getBuxPlayerStats()` work
- [x] **0.3.6** Update `CLAUDE.md` with new implementation address

### 0.4 Service Updates (Not Required)
- [x] **0.4.1** BUX Minter does NOT need V7 ABI - the new functions are read-only stats queries, not used by the betting flow
- [x] **0.4.2** No BUX Minter redeploy needed
- [x] **0.4.3** Stats queries will be done by the admin dashboard (Phase 1), not BUX Minter

### Key Decisions Made
1. **Stopped writing to combined stats**: `_processSettlement()` now ONLY writes to new `buxPlayerStats` and `buxAccounting` - it no longer updates the old combined `playerStats` mapping
2. **No historical data backfill**: Stats start at 0 after V7 upgrade. New BUX bets will populate the stats going forward. Old combined `playerStats` preserved for historical reference but no longer written to.
3. **BUX Minter unchanged**: The betting flow (submitCommitment, placeBet, settleBet) is unchanged. Only added view functions for stats queries.

### Files Created/Modified
- `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` - V7 structs, storage, functions
- `contracts/bux-booster-game/contracts/mocks/MockERC20.sol` - Test mock
- `contracts/bux-booster-game/test/BuxBoosterGame.v7.test.js` - 12 passing tests
- `contracts/bux-booster-game/scripts/upgrade-to-v7.js` - Deployment script

---

---

## Phase 1: Backend - Stats Module ✅ COMPLETE

**Completed**: February 3, 2026

### 1.1 Dependencies & Config ✅
- [x] **1.1.1** No new dependencies needed - `Req` library is already available in the project
- [x] **1.1.2** (Simplified) RPC URL hardcoded in module as `@rpc_url "https://rpc.roguechain.io/rpc"`
- [ ] **1.1.3** (Deferred to Phase 4) Admin emails config - will add when building admin routes
- [x] **1.1.4** (Simplified) Contract addresses hardcoded as module attributes:
  ```elixir
  @bux_booster_game "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"
  @rogue_bankroll "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  @bux_token "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"
  ```

### 1.2 Core Stats Module ✅
- [x] **1.2.1** Create `lib/blockster_v2/bux_booster_stats.ex` with module doc
- [x] **1.2.2** Implement `get_bux_global_stats/0` - calls `getBuxAccounting()`
- [x] **1.2.3** Implement `get_rogue_global_stats/0` - calls `buxBoosterAccounting()`
- [x] **1.2.4** Implement `get_bux_player_stats/1` - calls `getBuxPlayerStats(address)`
- [x] **1.2.5** Implement `get_rogue_player_stats/1` - calls `buxBoosterPlayerStats(address)`
- [x] **1.2.6** Implement `get_player_stats/1` - returns both BUX and ROGUE stats (parallel queries)
- [x] **1.2.7** Implement `get_house_balances/0` - queries both contracts (parallel queries)
- [x] **1.2.8** Add ABI encoding/decoding helper functions
- [x] **1.2.9** Add error handling for RPC failures

### 1.3 Contract Queries Module ✅
- [x] **1.3.1** (Simplified) All in single module `bux_booster_stats.ex` - no need for separate file
- [x] **1.3.2** Implement `eth_call/2` - raw eth_call wrapper using Req
- [x] **1.3.3** Implement `encode_address/1` - ABI address encoding (left-pad to 32 bytes)
- [x] **1.3.4** Implement decode functions: `decode_accounting_result/1`, `decode_bux_player_stats/1`, `decode_rogue_player_stats/1`
- [x] **1.3.5** Add function selectors for all query functions (calculated via keccak256)
- [x] **1.3.6** HTTP timeout configured at 15 seconds

### 1.4 Unit Tests
- [ ] **1.4.1** (Skipped) Tested manually with real contract data instead of mocks
- [ ] **1.4.2** (Skipped) ABI encoding verified through successful queries
- [ ] **1.4.3** (Skipped) ABI decoding verified through successful queries
- [x] **1.4.4** Tested with real RPC responses against mainnet contracts
- [x] **1.4.5** Error handling verified (e.g., ROGUE house balance required getHouseInfo() instead of houseBalance())

### Phase 1 Implementation Notes

#### File Created
- `lib/blockster_v2/bux_booster_stats.ex` - 430 lines

#### Function Selectors Used
```elixir
@get_bux_accounting_selector "0xb2cf35b4"       # getBuxAccounting()
@get_bux_player_stats_selector "0x2a07f39f"     # getBuxPlayerStats(address)
@bux_booster_accounting_selector "0xb9a6a46c"   # buxBoosterAccounting()
@bux_booster_player_stats_selector "0x08114368" # buxBoosterPlayerStats(address)
@token_configs_selector "0x1b69dc5f"            # tokenConfigs(address)
@get_house_info_selector "0x97b437bd"           # getHouseInfo()
```

#### Key Implementation Details

1. **Direct JSON-RPC Calls**: Uses `Req.post/2` for HTTP requests to the RPC endpoint. No ethers.js or web3 dependency needed.

2. **ABI Encoding**: Ethereum addresses are left-padded to 32 bytes (64 hex chars). Function selector is prepended.
   ```elixir
   defp encode_address(address) do
     address
     |> String.trim_leading("0x")
     |> String.downcase()
     |> String.pad_leading(64, "0")
   end
   ```

3. **ABI Decoding**: Response hex strings are split into 32-byte chunks and parsed:
   - `parse_uint256/1` - unsigned 256-bit integer
   - `parse_int256/1` - signed 256-bit integer (two's complement)
   - `decode_uint256_array/2` - fixed-size array of uint256
   - `decode_int256_array/2` - fixed-size array of int256

4. **Parallel Queries**: `get_player_stats/1` and `get_house_balances/0` use `Task.async/1` and `Task.await_many/2` for concurrent contract calls.

5. **ROGUEBankroll House Balance**: Initially tried `houseBalance()` which doesn't exist. Fixed to use `getHouseInfo()` which returns `(netBalance, totalBalance, minBetSize, maxBetSize)`.

#### Test Results (February 3, 2026)
```
BUX Global Stats:
  Total Bets: 2 (since V7 upgrade)
  Total Wins: 1
  Total Losses: 1
  House Profit: 0.2 BUX

ROGUE Global Stats:
  Total Bets: 564
  Total Wins: 287
  Total Losses: 277
  House Profit: 3,711,233 ROGUE

House Balances:
  BUX: 1,055,871.74 BUX
  ROGUE: 66,223,685,312.14 ROGUE

Player Stats (0x14C21eFf226D98D324CD2478A8579a0e63412d15):
  BUX: 0 bets (stats start fresh after V7)
  ROGUE: 36 bets, 15 wins, 21 losses, -2,000,562.88 ROGUE P/L
```

#### Usage Example
```elixir
alias BlocksterV2.BuxBoosterStats

# Global stats
{:ok, bux_stats} = BuxBoosterStats.get_bux_global_stats()
{:ok, rogue_stats} = BuxBoosterStats.get_rogue_global_stats()

# Player stats (parallel queries)
{:ok, player} = BuxBoosterStats.get_player_stats("0x14C21eFf226D98D324CD2478A8579a0e63412d15")
# Returns: %{wallet: "0x...", bux: %{...}, rogue: %{...}, combined: %{...}}

# House balances
{:ok, %{bux: bux_balance, rogue: rogue_balance}} = BuxBoosterStats.get_house_balances()
```

---

## Phase 2: Backend - Player Discovery ✅ COMPLETE (Feb 3, 2026)

### 2.1 Mnesia Table ✅
- [x] **2.1.1** Add `:bux_booster_players` table to `MnesiaInitializer`
- [ ] **2.1.2** Restart both nodes to create new table (required on next restart)
- [ ] **2.1.3** Verify table created: `:mnesia.table_info(:bux_booster_players, :size)`

### 2.2 Player Index Module ✅
- [x] **2.2.1** Create `lib/blockster_v2/bux_booster_stats/player_index.ex`
- [x] **2.2.2** Implement `index_players_from_events/1` - scans BetPlaced events
- [x] **2.2.3** Implement `get_all_player_addresses/0` - returns list from Mnesia
- [x] **2.2.4** Implement `get_player_count/0` - returns count
- [x] **2.2.5** Implement `upsert_player/2` - adds/updates player in index
- [x] **2.2.6** Implement `get_last_indexed_block/0` - for incremental indexing
- [x] **2.2.7** Add event log parsing for BetPlaced events

### 2.3 Background Indexer ✅
- [x] **2.3.1** Create `lib/blockster_v2/bux_booster_stats/indexer.ex` GenServer
- [x] **2.3.2** Schedule periodic indexing (every 5 minutes)
- [x] **2.3.3** Implement incremental indexing (from last block)
- [x] **2.3.4** Add to supervision tree in `application.ex`
- [x] **2.3.5** Use GlobalSingleton for cluster-wide single instance
- [x] **2.3.6** Add logging for indexing progress

### Phase 2 Implementation Notes

**Files Created:**
- `lib/blockster_v2/bux_booster_stats/player_index.ex` - Event scanning and Mnesia operations
- `lib/blockster_v2/bux_booster_stats/indexer.ex` - Background GenServer for periodic indexing

**Files Modified:**
- `lib/blockster_v2/mnesia_initializer.ex` - Added `:bux_booster_players` table (lines 492-505)
- `lib/blockster_v2/application.ex` - Added Indexer to supervision tree (line 48-49)
- `lib/blockster_v2/bux_booster_stats.ex` - Added player index integration functions (lines 470-586)

**Mnesia Table Schema:**
```elixir
%{
  name: :bux_booster_players,
  type: :set,
  attributes: [
    :wallet_address,       # PRIMARY KEY - lowercase 0x-prefixed
    :first_bet_block,      # Block number of first bet
    :last_bet_block,       # Block number of most recent bet
    :total_bets_indexed,   # Count of bets found for this player
    :created_at,           # Unix timestamp when first indexed
    :updated_at            # Unix timestamp of last update
  ],
  index: [:last_bet_block]
}
```

**Event Topics Scanned:**
- BuxBoosterGame: `BetPlaced(bytes32,address,uint256,int8,uint8[])` - BUX bets
- ROGUEBankroll: `BuxBoosterBetPlaced(bytes32,address,uint256,uint256,uint256,uint256)` - ROGUE bets

**Indexer Behavior:**
- Uses `GlobalSingleton` for cluster-wide single instance (only one node indexes)
- Waits 30 seconds after startup before first index run
- Performs full historical scan on first run (from block 0)
- Incremental updates every 5 minutes (only scans new blocks)
- Stores progress in `:referral_poller_state` table with key `:bux_booster_players_index`
- Batched getLogs calls (10,000 blocks per batch) to avoid RPC limits

**Usage Examples:**
```elixir
# Check indexer status
BlocksterV2.BuxBoosterStats.Indexer.status()
# => %{running: true, indexing: false, total_players_indexed: 127, last_indexed_block: 12345678, ...}

# Manually trigger indexing
BlocksterV2.BuxBoosterStats.Indexer.index_now()

# Get all player addresses
BlocksterV2.BuxBoosterStats.get_all_player_addresses()
# => ["0x14c21eff...", "0xb6b4a437..."]

# Get paginated player stats
BlocksterV2.BuxBoosterStats.get_all_player_stats(page: 1, per_page: 50, sort_by: :total_bets)
# => {:ok, %{players: [...], total_count: 127, page: 1, per_page: 50, total_pages: 3}}
```

**BuxBoosterStats Integration:**
Added to `bux_booster_stats.ex`:
- `get_all_player_addresses/0` - Delegates to PlayerIndex
- `get_player_count/0` - Delegates to PlayerIndex
- `get_all_player_stats/1` - Paginated stats with parallel RPC queries
  - Options: `:page`, `:per_page`, `:sort_by`, `:sort_order`
  - Sort fields: `:total_bets`, `:bux_wagered`, `:bux_pnl`, `:rogue_wagered`, `:rogue_pnl`
  - Uses `Task.async_stream` with max_concurrency: 10 for parallel RPC calls

---

## Phase 3: Backend - Caching Layer ✅ COMPLETE

### 3.1 Cache GenServer
- [x] **3.1.1** Create `lib/blockster_v2/bux_booster_stats/cache.ex`
- [x] **3.1.2** Create ETS table for stats cache
- [x] **3.1.3** Implement `get_global_stats/0` - returns cached or fetches
- [x] **3.1.4** Implement `get_player_stats/1` - returns cached or fetches
- [x] **3.1.5** Implement `invalidate_global/0` - clears global cache
- [x] **3.1.6** Implement `invalidate_player/1` - clears player cache
- [x] **3.1.7** Add TTL: 5 minutes for global, 1 minute for player stats
- [x] **3.1.8** Add to supervision tree
- [x] **3.1.9** Add cache hit/miss logging (debug level)

### Implementation Notes (Feb 3, 2026)

**File Created**: `lib/blockster_v2/bux_booster_stats/cache.ex`

**ETS Table**: `:bux_booster_stats_cache`
- Type: `:set` with `:public` access and `read_concurrency: true`
- Entry format: `{key, value, expires_at_ms}`

**Cache Keys**:
- `:global_stats` - Combined BUX + ROGUE global stats (5 min TTL)
- `:house_balances` - House bankroll balances (5 min TTL)
- `{:player, address}` - Per-player stats (1 min TTL)

**Public API**:
```elixir
# Get cached stats (auto-fetch on miss)
Cache.get_global_stats()      # {:ok, stats} or {:error, reason}
Cache.get_house_balances()    # {:ok, balances} or {:error, reason}
Cache.get_player_stats(addr)  # {:ok, stats} or {:error, reason}

# Invalidation
Cache.invalidate_global()     # Clears global + house balances
Cache.invalidate_player(addr) # Clears specific player
Cache.invalidate_all()        # Clears entire cache

# Monitoring
Cache.cache_info()            # %{entries: n, memory_kb: m}
```

**Supervision**: Added to `application.ex` genserver_children list

---

## Phase 4: Admin Authentication ✅ COMPLETE

### 4.1 Admin Check Functions
- [x] **4.1.1** Add `is_admin?/1` function to `lib/blockster_v2/accounts.ex`
- [x] **4.1.2** Uses existing `is_admin` boolean field on User schema
- [x] **4.1.3** (Skipped) Unit test - function is simple pattern match

### 4.2 Router Pipeline
- [x] **4.2.1** Using existing `:admin` live_session with `AdminAuth` hook
- [x] **4.2.2** `AdminAuth` module already implements admin check in `on_mount`
- [x] **4.2.3** Flash message for unauthorized access (existing)
- [x] **4.2.4** Redirect non-admins to home page (existing)

### 4.3 Admin Routes
- [x] **4.3.1** Added BuxBooster stats routes to existing admin live_session

### Implementation Notes (Feb 3, 2026)

**Existing Infrastructure Used**:
- `User.is_admin` boolean field already exists in schema
- `AdminAuth` LiveView hook already exists at `lib/blockster_v2_web/live/admin_auth.ex`
- Admin live_session already configured in `router.ex`

**New Function**: `Accounts.is_admin?/1` added to `lib/blockster_v2/accounts.ex`
```elixir
def is_admin?(nil), do: false
def is_admin?(%User{is_admin: true}), do: true
def is_admin?(_), do: false
```

**Routes Added** (in existing admin live_session):
```elixir
live "/admin/stats", Admin.StatsLive.Index, :index
live "/admin/stats/players", Admin.StatsLive.Players, :index
live "/admin/stats/players/:address", Admin.StatsLive.PlayerDetail, :show
```

**Authentication Flow**:
1. User visits `/admin/stats/*`
2. `UserAuth` hook loads current_user
3. `AdminAuth` hook checks `current_user.is_admin`
4. If not admin → flash error + redirect to `/`

---

## Phase 5: Global Stats Page ✅ COMPLETE

### 5.1 LiveView Module
- [x] **5.1.1** Create directory `lib/blockster_v2_web/live/admin/stats_live/`
- [x] **5.1.2** Create `lib/blockster_v2_web/live/admin/stats_live/index.ex`
- [x] **5.1.3** Implement `mount/3` with loading state
- [x] **5.1.4** Implement `handle_info(:load_stats, socket)` with async fetch
- [x] **5.1.5** Implement `handle_async/3` for BUX global stats
- [x] **5.1.6** Implement `handle_async/3` for ROGUE global stats
- [x] **5.1.7** Implement `handle_async/3` for house balances
- [x] **5.1.8** Implement `handle_event("refresh", ...)` for manual refresh
- [x] **5.1.9** Add `format_token/1` helper (divide by 10^18, format with commas)
- [x] **5.1.10** Add player count display from indexer

### 5.2 Template (inline in index.ex)
- [x] **5.2.1** Header with title and refresh button
- [x] **5.2.2** "Last updated" timestamp with relative time display
- [x] **5.2.3** BUX stats card (blue theme) with all metrics
- [x] **5.2.4** ROGUE stats card (yellow theme) with all metrics
- [x] **5.2.5** Loading skeleton states (pulse animation)
- [x] **5.2.6** House balances section (BUX blue, ROGUE yellow)
- [x] **5.2.7** Profit/loss styled green/red
- [x] **5.2.8** Responsive grid layout (1 col mobile, 2 col desktop)
- [x] **5.2.9** "View All Players" navigation button

### Implementation Notes (Feb 3, 2026)

**File Created**: `lib/blockster_v2_web/live/admin/stats_live/index.ex`

**Key Features**:
- Uses `Cache.get_global_stats()` which returns `{:ok, %{bux: bux_stats, rogue: rogue_stats, ...}}`
- Three parallel async fetches: global stats, house balances, player count
- Refresh button invalidates cache via `Cache.invalidate_all()`
- Time ago display for last updated timestamp

**Stats Displayed**:
| BUX Card | ROGUE Card |
|----------|------------|
| Total Bets | Total Bets |
| Wins (green) | Wins (green) |
| Losses (red) | Losses (red) |
| Player Win Rate | Player Win Rate |
| Volume Wagered | Volume Wagered |
| Total Payouts | Total Payouts |
| House Profit (+green/-red) | House Profit (+green/-red) |
| Largest Bet | Largest Bet |
| Largest Win | Largest Win |

**House Balances Section**:
- BUX House Balance (blue background)
- ROGUE House Balance (yellow background)

**Helper Functions**:
```elixir
# Format wei to human-readable
defp format_token(wei) when is_integer(wei) do
  amount = wei / 1_000_000_000_000_000_000
  Number.Delimit.number_to_delimited(Float.round(amount, 2))
end

# Calculate win rate
defp win_rate(wins, total) when total > 0, do: Float.round(wins / total * 100, 2)

# Relative time display
defp time_ago(datetime) do
  # Returns "X seconds/minutes/hours/days ago"
end
```

---

## Phase 6: Players List Page ✅ COMPLETE

### 6.1 LiveView Module
- [x] **6.1.1** Create `lib/blockster_v2_web/live/admin/stats_live/players.ex`
- [x] **6.1.2** Implement `mount/3` with pagination state
- [x] **6.1.3** Implement `load_players_async/1` helper
- [x] **6.1.4** Implement `handle_event("sort", ...)` for column sorting
- [x] **6.1.5** Implement `handle_event("search", ...)` (placeholder - search not yet wired)
- [x] **6.1.6** Implement `handle_event("page", ...)` for pagination
- [x] **6.1.7** Implement `handle_async(:load_players, ...)` handler
- [x] **6.1.8** (Deferred) Debounced search - search functionality placeholder only

### 6.2 Stats Module Updates (Already Done in Phase 1)
- [x] **6.2.1** `get_all_player_stats/1` already exists in `BuxBoosterStats` module
- [x] **6.2.2** Accepts options: page, per_page, sort_by, sort_order
- [x] **6.2.3** Pagination logic implemented
- [x] **6.2.4** Sorting logic implemented
- [x] **6.2.5** (Deferred) Wallet address search filter

### 6.3 Template (inline in players.ex)
- [x] **6.3.1** Header with player count
- [x] **6.3.2** (Commented out) Search input placeholder
- [x] **6.3.3** Sortable table headers with click handlers
- [x] **6.3.4** Columns: Wallet, Total Bets, BUX Wagered, BUX P/L, ROGUE Wagered, ROGUE P/L
- [x] **6.3.5** Sort indicator arrows (↑/↓)
- [x] **6.3.6** Pagination controls with ellipsis for large page counts
- [x] **6.3.7** "Details →" link for each row
- [x] **6.3.8** P/L styled green/red
- [x] **6.3.9** Loading spinner for table
- [x] **6.3.10** Roguescan links for wallet addresses

### Implementation Notes (Feb 3, 2026)

**File Created**: `lib/blockster_v2_web/live/admin/stats_live/players.ex`

**Key Features**:
- 50 players per page (`@per_page 50`)
- Sortable by: total_bets, bux_wagered, bux_pnl, rogue_wagered, rogue_pnl
- Toggle sort order on same field click
- Smart pagination (shows 1, 2, 3, ..., N for large page counts)

**Sortable Columns**:
| Column | Sort Key |
|--------|----------|
| Total Bets | `:total_bets` |
| BUX Wagered | `:bux_wagered` |
| BUX P/L | `:bux_pnl` |
| ROGUE Wagered | `:rogue_wagered` |
| ROGUE P/L | `:rogue_pnl` |

**Number Formatting** (with abbreviations):
```elixir
defp format_token(wei) when is_integer(wei) do
  amount = wei / 1_000_000_000_000_000_000
  cond do
    amount >= 1_000_000_000 -> "#{Float.round(amount / 1_000_000_000, 2)}B"
    amount >= 1_000_000 -> "#{Float.round(amount / 1_000_000, 2)}M"
    amount >= 1_000 -> "#{Float.round(amount / 1_000, 2)}K"
    true -> Number.Delimit.number_to_delimited(Float.round(amount, 2))
  end
end
```

**Pagination Logic**:
```elixir
# Shows: [1] [2] [3] [...] [50] for large page counts
# Or: [1] [...] [24] [25] [26] [...] [50] when in middle
defp pagination_range(current, total) when total <= 7 do
  1..total |> Enum.to_list()
end
defp pagination_range(current, total) do
  cond do
    current <= 4 -> [1, 2, 3, 4, 5, :ellipsis, total]
    current >= total - 3 -> [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]
    true -> [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
  end
end
```

---

## Phase 7: Player Detail Page ✅ COMPLETE

### 7.1 LiveView Module
- [x] **7.1.1** Create `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex`
- [x] **7.1.2** Implement `mount/3` - extract address from params
- [x] **7.1.3** Implement async stats loading via Cache
- [x] **7.1.4** Implement `handle_async/3` for player stats
- [x] **7.1.5** Add difficulty level names mapping constant
- [x] **7.1.6** Implement refresh with cache invalidation

### 7.2 Template (inline in player_detail.ex)
- [x] **7.2.1** Header with wallet address and Roguescan link
- [x] **7.2.2** BUX stats card with all fields
- [x] **7.2.3** ROGUE stats card with all fields
- [x] **7.2.4** Per-difficulty breakdown table (BUX only)
- [x] **7.2.5** Difficulty level names and multipliers
- [x] **7.2.6** P/L per difficulty with green/red styling
- [x] **7.2.7** Loading spinner state
- [x] **7.2.8** "Back to Players" navigation
- [x] **7.2.9** Combined summary section
- [x] **7.2.10** Note about ROGUE not having per-difficulty stats

### Implementation Notes (Feb 3, 2026)

**File Created**: `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex`

**Key Features**:
- Uses `Cache.get_player_stats(wallet)` for cached stats
- Refresh button calls `Cache.invalidate_player(wallet)` first
- Full wallet address displayed with Roguescan link
- BUX and ROGUE stats in side-by-side cards
- Per-difficulty breakdown table for BUX (V7 feature)

**Difficulty Level Mapping**:
```elixir
@difficulty_labels [
  {0, "Win One 5-flip", "1.02x"},
  {1, "Win One 4-flip", "1.05x"},
  {2, "Win One 3-flip", "1.13x"},
  {3, "Win One 2-flip", "1.32x"},
  {4, "Single Flip", "1.98x"},
  {5, "Win All 2-flip", "3.96x"},
  {6, "Win All 3-flip", "7.92x"},
  {7, "Win All 4-flip", "15.84x"},
  {8, "Win All 5-flip", "31.68x"}
]
```

**Stats Displayed Per Currency**:
| Field | Description |
|-------|-------------|
| Total Bets | Count of bets placed |
| Wins | Count of winning bets (green) |
| Losses | Count of losing bets (red) |
| Win Rate | Wins / Total Bets * 100 |
| Total Wagered | Sum of all bet amounts |
| Total Winnings | Sum of profit from wins (green) |
| Total Losses | Sum of amounts lost (red) |
| Net P/L | Total Winnings - Total Losses |

**Per-Difficulty Table** (BUX only):
- Shows bet count and P/L for each of 9 difficulty levels
- Rows with 0 bets shown with gray background
- P/L formatted with +/- prefix and green/red color

**Combined Summary Section**:
- Total Bets (BUX + ROGUE)
- Total Wins (BUX + ROGUE)
- Total Losses (BUX + ROGUE)

---

## Phase 8: Testing & Polish

### 8.1 Integration Testing
- [x] **8.1.1** Test global stats page loads correctly (compiles, returns 302 for auth)
- [ ] **8.1.2** Test players list pagination works
- [ ] **8.1.3** Test players list sorting works
- [ ] **8.1.4** Test players list search works
- [ ] **8.1.5** Test player detail page loads for valid address
- [ ] **8.1.6** Test player detail page handles invalid address
- [x] **8.1.7** Test admin authentication blocks non-admins (uses existing AdminAuth hook)
- [ ] **8.1.8** Test refresh button updates stats

### 8.2 Edge Cases
- [x] **8.2.1** Handle player with zero bets (shows "No stats found" message)
- [x] **8.2.2** Handle player with only BUX bets (ROGUE shows zeros)
- [x] **8.2.3** Handle player with only ROGUE bets (BUX shows zeros)
- [x] **8.2.4** Handle RPC timeout gracefully (async handlers catch errors)
- [x] **8.2.5** Handle RPC error gracefully (shows loading state fails gracefully)
- [x] **8.2.6** Handle empty players list (shows "No players found" message)

### 8.3 UI Polish
- [x] **8.3.1** Add loading spinners to all async operations (spinner + pulse skeletons)
- [x] **8.3.2** Add error messages for failed loads (handled via empty state messages)
- [x] **8.3.3** Ensure mobile responsiveness on all pages (grid-cols-1 md:grid-cols-2)
- [x] **8.3.4** Add hover states to table rows (hover:bg-gray-50)
- [x] **8.3.5** Add cursor-pointer to all clickable elements
- [x] **8.3.6** Use consistent number formatting throughout (format_token/1, format_pnl/1)
- [ ] **8.3.7** Add tooltips for abbreviations if needed

### 8.4 Documentation
- [x] **8.4.1** Update docs/bux_booster_stats.md with implementation notes
- [x] **8.4.2** V7 contract details already in doc
- [x] **8.4.3** Admin access requirements documented (AdminAuth hook)
- [x] **8.4.4** Add inline code comments (moduledocs added)

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

| Phase | Tasks | Status | Completed |
|-------|-------|--------|-----------|
| 0. Contract V7 | 29 tasks | ✅ Complete | Feb 2026 |
| 1. Stats Module | 24 tasks | ✅ Complete | Feb 3, 2026 |
| 2. Player Discovery | 16 tasks | ✅ Complete | Feb 3, 2026 |
| 3. Caching | 9 tasks | ✅ Complete | Feb 3, 2026 |
| 4. Admin Auth | 8 tasks | ✅ Complete | Feb 3, 2026 |
| 5. Global Stats Page | 19 tasks | ✅ Complete | Feb 3, 2026 |
| 6. Players List | 23 tasks | ✅ Complete | Feb 3, 2026 |
| 7. Player Detail | 15 tasks | ✅ Complete | Feb 3, 2026 |
| 8. Testing & Polish | 25 tasks | ⏳ Pending | - |
| 9. Deployment | 15 tasks | ⏳ Pending | - |
| **TOTAL** | **183 tasks** | **8/10 phases** | - |

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

---

## Phase 10: Simplification - Mnesia-Based User Stats (CURRENT)

### Background: Why the Current Approach is Overengineered

The current implementation has unnecessary complexity:

1. **PlayerIndex** - Scans blockchain events to find players who have bet
2. **Cache GenServer** - Caches on-chain stats with TTL
3. **On-chain queries** - Fetches stats from contracts for every player

**Problems:**
- Blockchain event scanning is slow and unreliable (keccak256 vs sha3_256 hashing issues)
- We already have `bux_booster_onchain_games` Mnesia table with ALL bet data
- Every user is a potential player - we should track ALL users, even with zero bets
- On-chain queries are slow and rate-limited

### The Simpler Approach

**Key insight**: We already track every bet in Mnesia (`bux_booster_onchain_games`). Instead of:
1. Scanning blockchain for players → Query on-chain for each player's stats

We should:
1. **New Mnesia table `user_betting_stats`** - pre-calculated stats per user (BUX and ROGUE separately)
2. **Every user gets a record on signup** - created with all zeros, so ALL users exist in Mnesia
3. **Updated on every bet settlement** - keeps stats current in real-time
4. **Page load queries Mnesia ONLY** - no PostgreSQL hit, just sorted query on `user_betting_stats`
5. **Backfill for existing users** - one-time migration creates records for ALL existing users + populates historical bet data
6. **No blockchain scanning, no on-chain queries per player** - just fast Mnesia lookups

### 10.1 Files to Delete (Unnecessary)

| File | Reason |
|------|--------|
| `lib/blockster_v2/bux_booster_stats/player_index.ex` | No longer needed - use users table |
| `lib/blockster_v2/bux_booster_stats/indexer.ex` | No longer needed - no blockchain scanning |
| `lib/blockster_v2/bux_booster_stats/cache.ex` | No longer needed - Mnesia is the cache |

### 10.2 New Mnesia Table: `user_betting_stats`

Add to `MnesiaInitializer`:

```elixir
:mnesia.create_table(:user_betting_stats, [
  attributes: [
    :user_id,           # Primary key (integer)
    :wallet_address,    # Stored here so we don't need to hit PostgreSQL on page load
    # BUX stats
    :bux_total_bets,
    :bux_wins,
    :bux_losses,
    :bux_total_wagered, # in wei
    :bux_total_winnings,
    :bux_total_losses,
    :bux_net_pnl,
    # ROGUE stats
    :rogue_total_bets,
    :rogue_wins,
    :rogue_losses,
    :rogue_total_wagered,
    :rogue_total_winnings,
    :rogue_total_losses,
    :rogue_net_pnl,
    # Timestamps
    :first_bet_at,
    :last_bet_at,
    :updated_at
  ],
  disc_copies: [node()],
  type: :set,
  index: [:bux_total_wagered, :rogue_total_wagered]  # For sorting by volume
])
```

**Record structure** (21 fields, 0-indexed):
| Index | Field | Type |
|-------|-------|------|
| 0 | :user_betting_stats | table name |
| 1 | user_id | integer (primary key) |
| 2 | wallet_address | string |
| 3 | bux_total_bets | integer |
| 4 | bux_wins | integer |
| 5 | bux_losses | integer |
| 6 | bux_total_wagered | integer (wei) |
| 7 | bux_total_winnings | integer (wei) |
| 8 | bux_total_losses | integer (wei) |
| 9 | bux_net_pnl | integer (wei, can be negative) |
| 10 | rogue_total_bets | integer |
| 11 | rogue_wins | integer |
| 12 | rogue_losses | integer |
| 13 | rogue_total_wagered | integer (wei) |
| 14 | rogue_total_winnings | integer (wei) |
| 15 | rogue_total_losses | integer (wei) |
| 16 | rogue_net_pnl | integer (wei, can be negative) |
| 17 | first_bet_at | integer (unix ms) or nil |
| 18 | last_bet_at | integer (unix ms) or nil |
| 19 | updated_at | integer (unix ms) |

### 10.3 Create Record on User Signup

In `Accounts.create_user/1` or wherever users are created, also create their betting stats record:

```elixir
def create_user_betting_stats(user_id, wallet_address) do
  now = System.system_time(:millisecond)
  record = {:user_betting_stats, user_id, wallet_address,
    0, 0, 0, 0, 0, 0, 0,  # BUX stats (all zeros)
    0, 0, 0, 0, 0, 0, 0,  # ROGUE stats (all zeros)
    nil, nil, now}        # timestamps
  :mnesia.dirty_write(record)
end
```

### 10.3 Update Stats on Bet Settlement

In `BuxBoosterOnchain.settle_game/1`, after successful settlement:

```elixir
defp update_user_betting_stats(user_id, token, bet_amount, won, payout) do
  # Record should already exist (created on signup)
  # But handle missing record gracefully just in case
  [record] = case :mnesia.dirty_read(:user_betting_stats, user_id) do
    [existing] -> [existing]
    [] ->
      Logger.warning("[BuxBoosterOnchain] Missing user_betting_stats for user #{user_id}")
      []
  end

  return if record == nil

  # Update the appropriate token stats
  now = System.system_time(:millisecond)
  first_bet_at = elem(record, 17) || now  # Set first_bet_at if nil

  updated = case token do
    "BUX" -> update_bux_stats(record, bet_amount, won, payout, now, first_bet_at)
    "ROGUE" -> update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at)
    _ -> record
  end

  :mnesia.dirty_write(updated)
end

defp update_bux_stats(record, bet_amount, won, payout, now, first_bet_at) do
  bet_amount_wei = trunc(bet_amount * 1_000_000_000_000_000_000)
  payout_wei = trunc(payout * 1_000_000_000_000_000_000)

  record
  |> put_elem(3, elem(record, 3) + 1)  # bux_total_bets
  |> put_elem(4, elem(record, 4) + (if won, do: 1, else: 0))  # bux_wins
  |> put_elem(5, elem(record, 5) + (if won, do: 0, else: 1))  # bux_losses
  |> put_elem(6, elem(record, 6) + bet_amount_wei)  # bux_total_wagered
  |> put_elem(7, elem(record, 7) + (if won, do: payout_wei - bet_amount_wei, else: 0))  # bux_total_winnings
  |> put_elem(8, elem(record, 8) + (if won, do: 0, else: bet_amount_wei))  # bux_total_losses
  |> put_elem(9, elem(record, 9) + (if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei))  # bux_net_pnl
  |> put_elem(17, first_bet_at)  # first_bet_at
  |> put_elem(18, now)  # last_bet_at
  |> put_elem(19, now)  # updated_at
end

# Similar for update_rogue_stats/6 (indices 10-16 for ROGUE stats)
```

### 10.5 Simplified BuxBoosterStats Module

Replace complex on-chain querying with simple Mnesia queries:

```elixir
defmodule BlocksterV2.BuxBoosterStats do
  @moduledoc """
  Provides betting statistics from Mnesia user_betting_stats table.
  All stats are updated in real-time on bet settlement.
  Queries Mnesia ONLY - no PostgreSQL hit on page load.
  """

  @doc """
  Get all users with their betting stats, sorted by volume.
  Queries user_betting_stats Mnesia table directly - no PostgreSQL.
  """
  def get_all_player_stats(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    sort_by = Keyword.get(opts, :sort_by, :total_bets)
    sort_order = Keyword.get(opts, :sort_order, :desc)

    # Get ALL records from user_betting_stats (every user has one)
    all_records = :mnesia.dirty_match_object(
      {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )

    # Convert to maps
    users_with_stats = Enum.map(all_records, &record_to_map/1)

    # Sort
    sorted = sort_users(users_with_stats, sort_by, sort_order)

    # Paginate
    total_count = length(sorted)
    total_pages = max(1, ceil(total_count / per_page))
    offset = (page - 1) * per_page

    paginated = sorted |> Enum.drop(offset) |> Enum.take(per_page)

    {:ok, %{
      players: paginated,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: total_pages
    }}
  end

  defp get_user_stats(user_id) do
    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] -> record_to_map(record)
      [] -> empty_stats()
    end
  end

  defp record_to_map(record) do
    %{
      user_id: elem(record, 1),
      wallet: elem(record, 2),
      bux: %{
        total_bets: elem(record, 3),
        wins: elem(record, 4),
        losses: elem(record, 5),
        total_wagered: elem(record, 6),
        net_pnl: elem(record, 9)
      },
      rogue: %{
        total_bets: elem(record, 10),
        wins: elem(record, 11),
        losses: elem(record, 12),
        total_wagered: elem(record, 13),
        net_pnl: elem(record, 16)
      },
      combined: %{
        total_bets: elem(record, 3) + elem(record, 10)
      }
    }
  end

  defp sort_users(users, :total_bets, order) do
    Enum.sort_by(users, & &1.combined.total_bets, order)
  end

  defp sort_users(users, :bux_wagered, order) do
    Enum.sort_by(users, & &1.bux.total_wagered, order)
  end

  defp sort_users(users, :bux_pnl, order) do
    Enum.sort_by(users, & &1.bux.net_pnl, order)
  end

  defp sort_users(users, :rogue_wagered, order) do
    Enum.sort_by(users, & &1.rogue.total_wagered, order)
  end

  defp sort_users(users, :rogue_pnl, order) do
    Enum.sort_by(users, & &1.rogue.net_pnl, order)
  end

  defp sort_users(users, _, order) do
    # Default: sort by total bets
    Enum.sort_by(users, & &1.combined.total_bets, order)
  end

  @doc """
  Get count of users who have placed at least one bet.
  """
  def get_player_count do
    :mnesia.dirty_match_object(
      {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.count(fn record -> elem(record, 3) > 0 or elem(record, 10) > 0 end)
  end
end
```

### 10.6 Simplified Players LiveView

```elixir
defmodule BlocksterV2Web.Admin.StatsLive.Players do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats

  def mount(_params, _session, socket) do
    socket = assign(socket,
      players: [],
      page: 1,
      total_pages: 1,
      total_count: 0,
      sort_by: :bux_total_wagered,  # Primary sort: BUX volume
      sort_order: :desc,
      loading: true
    )

    if connected?(socket), do: send(self(), :load_players)

    {:ok, socket}
  end

  def handle_info(:load_players, socket) do
    %{page: page, sort_by: sort_by, sort_order: sort_order} = socket.assigns

    {:ok, result} = BuxBoosterStats.get_all_player_stats(
      page: page,
      per_page: 50,
      sort_by: sort_by,
      sort_order: sort_order
    )

    {:noreply, assign(socket,
      players: result.players,
      total_count: result.total_count,
      total_pages: result.total_pages,
      loading: false
    )}
  end
end
```

### 10.6 Global Stats - Keep On-Chain Queries

Global stats (total bets across all users, house profit, etc.) should still come from on-chain:
- `BuxBoosterGame.getBuxAccounting()` for BUX global stats
- `ROGUEBankroll.buxBoosterAccounting()` for ROGUE global stats

These are single queries, not per-user, so the overhead is acceptable.

### 10.7 Migration: Backfill Historical Stats

Create a one-time migration script to populate `user_betting_stats` from existing `bux_booster_onchain_games`:

```elixir
defmodule BlocksterV2.BuxBoosterStats.Backfill do
  @moduledoc """
  One-time backfill of user_betting_stats for ALL existing users.
  Creates records for every user (with zeros for those who haven't bet).
  Run once after deploying the new table.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  def run do
    IO.puts("Starting backfill...")

    # Step 1: Get ALL users from PostgreSQL (one-time read)
    all_users = Repo.all(
      from u in User,
      select: %{id: u.id, wallet_address: u.wallet_address}
    )
    IO.puts("Found #{length(all_users)} users in PostgreSQL")

    # Step 2: Get all settled games from Mnesia
    all_games = :mnesia.dirty_match_object(
      {:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :settled, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    IO.puts("Found #{length(all_games)} settled games in Mnesia")

    # Step 3: Group games by user_id
    games_by_user = Enum.group_by(all_games, fn game -> elem(game, 2) end)

    # Step 4: Create a record for EVERY user
    now = System.system_time(:millisecond)
    users_with_bets = 0
    users_without_bets = 0

    Enum.each(all_users, fn user ->
      games = Map.get(games_by_user, user.id, [])

      record = if Enum.empty?(games) do
        # User has no bets - create empty record
        create_empty_record(user.id, user.wallet_address, now)
      else
        # User has bets - calculate stats
        calculate_stats_from_games(user.id, user.wallet_address, games, now)
      end

      :mnesia.dirty_write(record)
    end)

    users_with_bets = map_size(games_by_user)
    users_without_bets = length(all_users) - users_with_bets

    IO.puts("Backfill complete:")
    IO.puts("  - #{users_with_bets} users with betting history")
    IO.puts("  - #{users_without_bets} users with zero bets")
    IO.puts("  - #{length(all_users)} total records created")
  end

  defp create_empty_record(user_id, wallet_address, now) do
    {:user_betting_stats, user_id, wallet_address,
      0, 0, 0, 0, 0, 0, 0,  # BUX stats (all zeros)
      0, 0, 0, 0, 0, 0, 0,  # ROGUE stats (all zeros)
      nil, nil, now}        # first_bet_at, last_bet_at, updated_at
  end

  defp calculate_stats_from_games(user_id, wallet_address, games, now) do
    # Separate BUX and ROGUE games
    bux_games = Enum.filter(games, fn g -> elem(g, 9) == "BUX" end)
    rogue_games = Enum.filter(games, fn g -> elem(g, 9) == "ROGUE" end)

    bux = aggregate_games(bux_games)
    rogue = aggregate_games(rogue_games)

    first_bet = games |> Enum.map(&elem(&1, 20)) |> Enum.min(fn -> nil end)
    last_bet = games |> Enum.map(&elem(&1, 21)) |> Enum.max(fn -> nil end)

    {:user_betting_stats, user_id, wallet_address,
      bux.total_bets, bux.wins, bux.losses,
      bux.total_wagered, bux.total_winnings, bux.total_losses, bux.net_pnl,
      rogue.total_bets, rogue.wins, rogue.losses,
      rogue.total_wagered, rogue.total_winnings, rogue.total_losses, rogue.net_pnl,
      first_bet, last_bet, now}
  end

  defp aggregate_games([]) do
    %{total_bets: 0, wins: 0, losses: 0, total_wagered: 0, total_winnings: 0, total_losses: 0, net_pnl: 0}
  end

  defp aggregate_games(games) do
    Enum.reduce(games, %{total_bets: 0, wins: 0, losses: 0, total_wagered: 0, total_winnings: 0, total_losses: 0, net_pnl: 0}, fn game, acc ->
      bet_amount = to_wei(elem(game, 10))
      won = elem(game, 15)
      payout = to_wei(elem(game, 16))

      %{acc |
        total_bets: acc.total_bets + 1,
        wins: acc.wins + (if won, do: 1, else: 0),
        losses: acc.losses + (if won, do: 0, else: 1),
        total_wagered: acc.total_wagered + bet_amount,
        total_winnings: acc.total_winnings + (if won, do: payout - bet_amount, else: 0),
        total_losses: acc.total_losses + (if won, do: 0, else: bet_amount),
        net_pnl: acc.net_pnl + (if won, do: payout - bet_amount, else: -bet_amount)
      }
    end)
  end

  defp to_wei(nil), do: 0
  defp to_wei(amount) when is_float(amount), do: trunc(amount * 1_000_000_000_000_000_000)
  defp to_wei(amount) when is_integer(amount), do: amount * 1_000_000_000_000_000_000
end
```

**Run the backfill** (after table is created and nodes restarted):

### Local Development

```bash
# Start node1 first
elixir --sname node1 -S mix phx.server

# In another terminal, run the backfill script:
elixir --sname backfill$(date +%s) -S mix run -e '
Node.connect(:"node1@YOUR-HOSTNAME")
Process.sleep(3000)
result = :rpc.call(:"node1@YOUR-HOSTNAME", BlocksterV2.BuxBoosterStats.Backfill, :run, [], 60_000)
IO.inspect(result)
'
```

Replace `YOUR-HOSTNAME` with your machine name (e.g., `Adams-iMac-Pro`).

### Production (Fly.io)

SSH into the Fly machine and run directly:

```bash
# SSH into the app
fly ssh console --app blockster-v2

# In the remote shell, run:
/app/bin/blockster_v2 rpc 'BlocksterV2.BuxBoosterStats.Backfill.run()'
```

Or run directly without interactive shell:

```bash
fly ssh console --app blockster-v2 -C "/app/bin/blockster_v2 rpc 'BlocksterV2.BuxBoosterStats.Backfill.run()'"
```

### Check Backfill Status

```elixir
BlocksterV2.BuxBoosterStats.Backfill.status()
# Returns: %{postgresql_users: 53, mnesia_records: 53, coverage_percent: 100.0, ...}
```

### 10.8 Detailed Implementation Guide

This section provides exact code changes and commands for implementing the simplified stats system.

---

#### STEP 1: Delete Unnecessary Files

**Files to delete:**
```bash
rm lib/blockster_v2/bux_booster_stats/player_index.ex
rm lib/blockster_v2/bux_booster_stats/indexer.ex
rm lib/blockster_v2/bux_booster_stats/cache.ex
```

---

#### STEP 2: Remove Indexer and Cache from Supervision Tree

**File:** `lib/blockster_v2/application.ex`

Search for and remove any references to:
- `BlocksterV2.BuxBoosterStats.Indexer`
- `BlocksterV2.BuxBoosterStats.Cache`

If these lines exist in the `children` list, delete them:
```elixir
# DELETE if present:
{BlocksterV2.BuxBoosterStats.Indexer, []},
{BlocksterV2.BuxBoosterStats.Cache, []},
```

---

#### STEP 3: Remove Old Mnesia Table Definition

**File:** `lib/blockster_v2/mnesia_initializer.ex`

Search for `:bux_booster_players` table definition and DELETE the entire block:
```elixir
# DELETE if present:
:mnesia.create_table(:bux_booster_players, [
  attributes: [...],
  ...
])
```

---

#### STEP 4: Add New Mnesia Table Definition

**File:** `lib/blockster_v2/mnesia_initializer.ex`

Add this table definition in the `create_tables/0` function (after other table definitions):

```elixir
# User betting stats - pre-calculated for instant page loads
:mnesia.create_table(:user_betting_stats, [
  attributes: [
    :user_id,             # Primary key (integer)
    :wallet_address,      # String - stored here to avoid PostgreSQL joins
    # BUX stats (7 fields)
    :bux_total_bets,      # integer
    :bux_wins,            # integer
    :bux_losses,          # integer
    :bux_total_wagered,   # integer (wei)
    :bux_total_winnings,  # integer (wei)
    :bux_total_losses,    # integer (wei)
    :bux_net_pnl,         # integer (wei, can be negative)
    # ROGUE stats (7 fields)
    :rogue_total_bets,    # integer
    :rogue_wins,          # integer
    :rogue_losses,        # integer
    :rogue_total_wagered, # integer (wei)
    :rogue_total_winnings,# integer (wei)
    :rogue_total_losses,  # integer (wei)
    :rogue_net_pnl,       # integer (wei, can be negative)
    # Timestamps (3 fields)
    :first_bet_at,        # integer (unix ms) or nil
    :last_bet_at,         # integer (unix ms) or nil
    :updated_at           # integer (unix ms)
  ],
  disc_copies: [node()],
  type: :set,
  index: [:bux_total_wagered, :rogue_total_wagered]
])
```

**Record indices (0-indexed, 20 elements total):**
| Index | Field |
|-------|-------|
| 0 | :user_betting_stats (table name) |
| 1 | user_id |
| 2 | wallet_address |
| 3 | bux_total_bets |
| 4 | bux_wins |
| 5 | bux_losses |
| 6 | bux_total_wagered |
| 7 | bux_total_winnings |
| 8 | bux_total_losses |
| 9 | bux_net_pnl |
| 10 | rogue_total_bets |
| 11 | rogue_wins |
| 12 | rogue_losses |
| 13 | rogue_total_wagered |
| 14 | rogue_total_winnings |
| 15 | rogue_total_losses |
| 16 | rogue_net_pnl |
| 17 | first_bet_at |
| 18 | last_bet_at |
| 19 | updated_at |

---

#### STEP 5: Add create_user_betting_stats/2 Function

**File:** `lib/blockster_v2/accounts.ex`

Add this function:

```elixir
@doc """
Creates a betting stats record for a user in Mnesia.
Called when a new user is created after wallet is assigned.
All stats start at zero.
"""
def create_user_betting_stats(user_id, wallet_address) when is_integer(user_id) do
  now = System.system_time(:millisecond)
  record = {:user_betting_stats,
    user_id,
    wallet_address || "",
    # BUX stats (all zeros)
    0, 0, 0, 0, 0, 0, 0,
    # ROGUE stats (all zeros)
    0, 0, 0, 0, 0, 0, 0,
    # Timestamps
    nil, nil, now
  }
  :mnesia.dirty_write(record)
  :ok
end
```

---

#### STEP 6: Call create_user_betting_stats on Signup

**File:** `lib/blockster_v2/accounts.ex`

Find the function that creates/updates users with wallet addresses. This is typically in `authenticate_new_user_with_fingerprint/1` or similar.

Add the call AFTER the user is created and has a wallet_address:

```elixir
# After user is created with wallet:
create_user_betting_stats(user.id, user.wallet_address)
```

**Example location** (find the right spot in your codebase):
```elixir
def authenticate_new_user_with_fingerprint(attrs) do
  # ... existing code that creates user ...

  case result do
    {:ok, user} ->
      # Create betting stats record for new user
      create_user_betting_stats(user.id, user.wallet_address)
      {:ok, user}
    error ->
      error
  end
end
```

---

#### STEP 7: Create Backfill Module

**File:** `lib/blockster_v2/bux_booster_stats/backfill.ex` (NEW FILE)

```elixir
defmodule BlocksterV2.BuxBoosterStats.Backfill do
  @moduledoc """
  One-time backfill of user_betting_stats for ALL existing users.
  Creates records for every user (with zeros for those who haven't bet).
  Populates historical betting data from bux_booster_onchain_games Mnesia table.

  Run once after deploying the new table:
    BlocksterV2.BuxBoosterStats.Backfill.run()
  """

  require Logger
  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  def run do
    Logger.info("[Backfill] Starting user_betting_stats backfill...")

    # Step 1: Get ALL users from PostgreSQL (one-time read)
    all_users = Repo.all(
      from u in User,
      select: %{id: u.id, wallet_address: u.wallet_address}
    )
    Logger.info("[Backfill] Found #{length(all_users)} users in PostgreSQL")

    # Step 2: Get all settled games from Mnesia
    all_games = :mnesia.dirty_match_object(
      {:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :settled, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    Logger.info("[Backfill] Found #{length(all_games)} settled games in Mnesia")

    # Step 3: Group games by user_id
    games_by_user = Enum.group_by(all_games, fn game -> elem(game, 2) end)

    # Step 4: Create a record for EVERY user
    now = System.system_time(:millisecond)

    Enum.each(all_users, fn user ->
      games = Map.get(games_by_user, user.id, [])

      record = if Enum.empty?(games) do
        create_empty_record(user.id, user.wallet_address, now)
      else
        calculate_stats_from_games(user.id, user.wallet_address, games, now)
      end

      :mnesia.dirty_write(record)
    end)

    users_with_bets = map_size(games_by_user)
    users_without_bets = length(all_users) - users_with_bets

    Logger.info("[Backfill] Complete!")
    Logger.info("[Backfill]   - #{users_with_bets} users with betting history")
    Logger.info("[Backfill]   - #{users_without_bets} users with zero bets")
    Logger.info("[Backfill]   - #{length(all_users)} total records created")

    {:ok, %{
      total_users: length(all_users),
      users_with_bets: users_with_bets,
      users_without_bets: users_without_bets
    }}
  end

  defp create_empty_record(user_id, wallet_address, now) do
    {:user_betting_stats,
      user_id,
      wallet_address || "",
      # BUX stats (all zeros)
      0, 0, 0, 0, 0, 0, 0,
      # ROGUE stats (all zeros)
      0, 0, 0, 0, 0, 0, 0,
      # Timestamps
      nil, nil, now
    }
  end

  defp calculate_stats_from_games(user_id, wallet_address, games, now) do
    # Separate BUX and ROGUE games
    # Token is at index 9 in bux_booster_onchain_games
    bux_games = Enum.filter(games, fn g -> elem(g, 9) == "BUX" end)
    rogue_games = Enum.filter(games, fn g -> elem(g, 9) == "ROGUE" end)

    bux = aggregate_games(bux_games)
    rogue = aggregate_games(rogue_games)

    # first_bet_at = min of created_at (index 20)
    # last_bet_at = max of settled_at (index 21)
    first_bet = games |> Enum.map(&elem(&1, 20)) |> Enum.filter(&(&1 != nil)) |> Enum.min(fn -> nil end)
    last_bet = games |> Enum.map(&elem(&1, 21)) |> Enum.filter(&(&1 != nil)) |> Enum.max(fn -> nil end)

    {:user_betting_stats,
      user_id,
      wallet_address || "",
      # BUX stats
      bux.total_bets, bux.wins, bux.losses,
      bux.total_wagered, bux.total_winnings, bux.total_losses, bux.net_pnl,
      # ROGUE stats
      rogue.total_bets, rogue.wins, rogue.losses,
      rogue.total_wagered, rogue.total_winnings, rogue.total_losses, rogue.net_pnl,
      # Timestamps
      first_bet, last_bet, now
    }
  end

  defp aggregate_games([]) do
    %{total_bets: 0, wins: 0, losses: 0, total_wagered: 0, total_winnings: 0, total_losses: 0, net_pnl: 0}
  end

  defp aggregate_games(games) do
    Enum.reduce(games, %{total_bets: 0, wins: 0, losses: 0, total_wagered: 0, total_winnings: 0, total_losses: 0, net_pnl: 0}, fn game, acc ->
      # bet_amount is at index 10 (float)
      # won is at index 15 (boolean)
      # payout is at index 16 (float)
      bet_amount = to_wei(elem(game, 10))
      won = elem(game, 15) == true
      payout = to_wei(elem(game, 16))

      profit = if won, do: payout - bet_amount, else: 0
      loss = if won, do: 0, else: bet_amount

      %{acc |
        total_bets: acc.total_bets + 1,
        wins: acc.wins + (if won, do: 1, else: 0),
        losses: acc.losses + (if won, do: 0, else: 1),
        total_wagered: acc.total_wagered + bet_amount,
        total_winnings: acc.total_winnings + profit,
        total_losses: acc.total_losses + loss,
        net_pnl: acc.net_pnl + (if won, do: profit, else: -loss)
      }
    end)
  end

  defp to_wei(nil), do: 0
  defp to_wei(amount) when is_float(amount), do: trunc(amount * 1_000_000_000_000_000_000)
  defp to_wei(amount) when is_integer(amount), do: amount * 1_000_000_000_000_000_000
end
```

---

#### STEP 8: Add update_user_betting_stats to BuxBoosterOnchain

**File:** `lib/blockster_v2/bux_booster_onchain.ex`

Add these functions:

```elixir
@doc """
Updates a user's betting stats in Mnesia after bet settlement.
Called from settle_game/1 after successful on-chain settlement.
"""
def update_user_betting_stats(user_id, token, bet_amount, won, payout) do
  case :mnesia.dirty_read(:user_betting_stats, user_id) do
    [record] ->
      now = System.system_time(:millisecond)
      first_bet_at = elem(record, 17) || now

      updated = case token do
        "BUX" -> update_bux_stats(record, bet_amount, won, payout, now, first_bet_at)
        "ROGUE" -> update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at)
        _ -> record
      end

      :mnesia.dirty_write(updated)
      :ok

    [] ->
      Logger.warning("[BuxBoosterOnchain] Missing user_betting_stats for user #{user_id}")
      :ok
  end
end

defp update_bux_stats(record, bet_amount, won, payout, now, first_bet_at) do
  bet_amount_wei = trunc(bet_amount * 1_000_000_000_000_000_000)
  payout_wei = trunc((payout || 0) * 1_000_000_000_000_000_000)
  profit = if won, do: payout_wei - bet_amount_wei, else: 0
  loss = if won, do: 0, else: bet_amount_wei

  record
  |> put_elem(3, elem(record, 3) + 1)                                  # bux_total_bets
  |> put_elem(4, elem(record, 4) + (if won, do: 1, else: 0))          # bux_wins
  |> put_elem(5, elem(record, 5) + (if won, do: 0, else: 1))          # bux_losses
  |> put_elem(6, elem(record, 6) + bet_amount_wei)                     # bux_total_wagered
  |> put_elem(7, elem(record, 7) + profit)                             # bux_total_winnings
  |> put_elem(8, elem(record, 8) + loss)                               # bux_total_losses
  |> put_elem(9, elem(record, 9) + (if won, do: profit, else: -loss)) # bux_net_pnl
  |> put_elem(17, first_bet_at)                                        # first_bet_at
  |> put_elem(18, now)                                                 # last_bet_at
  |> put_elem(19, now)                                                 # updated_at
end

defp update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at) do
  bet_amount_wei = trunc(bet_amount * 1_000_000_000_000_000_000)
  payout_wei = trunc((payout || 0) * 1_000_000_000_000_000_000)
  profit = if won, do: payout_wei - bet_amount_wei, else: 0
  loss = if won, do: 0, else: bet_amount_wei

  record
  |> put_elem(10, elem(record, 10) + 1)                                  # rogue_total_bets
  |> put_elem(11, elem(record, 11) + (if won, do: 1, else: 0))          # rogue_wins
  |> put_elem(12, elem(record, 12) + (if won, do: 0, else: 1))          # rogue_losses
  |> put_elem(13, elem(record, 13) + bet_amount_wei)                     # rogue_total_wagered
  |> put_elem(14, elem(record, 14) + profit)                             # rogue_total_winnings
  |> put_elem(15, elem(record, 15) + loss)                               # rogue_total_losses
  |> put_elem(16, elem(record, 16) + (if won, do: profit, else: -loss)) # rogue_net_pnl
  |> put_elem(17, first_bet_at)                                          # first_bet_at
  |> put_elem(18, now)                                                   # last_bet_at
  |> put_elem(19, now)                                                   # updated_at
end
```

---

#### STEP 9: Call update_user_betting_stats from settle_game/1

**File:** `lib/blockster_v2/bux_booster_onchain.ex`

Find the `settle_game/1` function and add the stats update call after successful settlement.

Look for where `{:ok, settlement_tx}` is returned and add:

```elixir
# After successful settlement, update user betting stats
update_user_betting_stats(user_id, token, bet_amount, won, payout)
```

**Example location** (find in settle_game/1):
```elixir
def settle_game(game_id) do
  # ... existing settlement code ...

  case BuxMinter.settle_bet(...) do
    {:ok, settlement_tx} ->
      # Update game record in Mnesia
      # ... existing code ...

      # Update user betting stats
      update_user_betting_stats(user_id, token, bet_amount, won, payout)

      {:ok, settlement_tx}

    {:error, reason} ->
      {:error, reason}
  end
end
```

---

#### STEP 10: Rewrite BuxBoosterStats Module

**File:** `lib/blockster_v2/bux_booster_stats.ex`

Replace the `get_all_player_stats/1` and `get_player_count/0` functions with these simpler versions:

```elixir
@doc """
Get all users with their betting stats, sorted by volume.
Queries user_betting_stats Mnesia table directly - no PostgreSQL.
"""
def get_all_player_stats(opts \\ []) do
  page = Keyword.get(opts, :page, 1)
  per_page = Keyword.get(opts, :per_page, 50)
  sort_by = Keyword.get(opts, :sort_by, :total_bets)
  sort_order = Keyword.get(opts, :sort_order, :desc)

  # Get ALL records from user_betting_stats
  # Match pattern has 20 elements (table name + 19 fields)
  all_records = :mnesia.dirty_match_object(
    {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
  )

  # Convert to maps
  users_with_stats = Enum.map(all_records, &record_to_map/1)

  # Sort
  sorted = sort_users(users_with_stats, sort_by, sort_order)

  # Paginate
  total_count = length(sorted)
  total_pages = max(1, ceil(total_count / per_page))
  offset = (page - 1) * per_page

  paginated = sorted |> Enum.drop(offset) |> Enum.take(per_page)

  {:ok, %{
    players: paginated,
    total_count: total_count,
    page: page,
    per_page: per_page,
    total_pages: total_pages
  }}
end

@doc """
Get count of users who have placed at least one bet.
"""
def get_player_count do
  :mnesia.dirty_match_object(
    {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
  )
  |> Enum.count(fn record -> elem(record, 3) > 0 or elem(record, 10) > 0 end)
end

defp record_to_map(record) do
  %{
    user_id: elem(record, 1),
    wallet: elem(record, 2),
    bux: %{
      total_bets: elem(record, 3),
      wins: elem(record, 4),
      losses: elem(record, 5),
      total_wagered: elem(record, 6),
      total_winnings: elem(record, 7),
      total_losses: elem(record, 8),
      net_pnl: elem(record, 9)
    },
    rogue: %{
      total_bets: elem(record, 10),
      wins: elem(record, 11),
      losses: elem(record, 12),
      total_wagered: elem(record, 13),
      total_winnings: elem(record, 14),
      total_losses: elem(record, 15),
      net_pnl: elem(record, 16)
    },
    combined: %{
      total_bets: elem(record, 3) + elem(record, 10)
    },
    first_bet_at: elem(record, 17),
    last_bet_at: elem(record, 18)
  }
end

defp sort_users(users, :total_bets, order), do: Enum.sort_by(users, & &1.combined.total_bets, order)
defp sort_users(users, :bux_wagered, order), do: Enum.sort_by(users, & &1.bux.total_wagered, order)
defp sort_users(users, :bux_pnl, order), do: Enum.sort_by(users, & &1.bux.net_pnl, order)
defp sort_users(users, :rogue_wagered, order), do: Enum.sort_by(users, & &1.rogue.total_wagered, order)
defp sort_users(users, :rogue_pnl, order), do: Enum.sort_by(users, & &1.rogue.net_pnl, order)
defp sort_users(users, _, order), do: Enum.sort_by(users, & &1.combined.total_bets, order)
```

**Also remove these old dependencies** from the module:
- Remove `alias BlocksterV2.BuxBoosterStats.PlayerIndex`
- Remove `alias BlocksterV2.BuxBoosterStats.Cache`
- Remove any calls to `PlayerIndex.*` or `Cache.*`

---

#### STEP 11: Update Players LiveView

**File:** `lib/blockster_v2_web/live/admin/stats_live/players.ex`

The LiveView should already be calling `BuxBoosterStats.get_all_player_stats/1`.
Verify the `load_players_async` function uses the correct call:

```elixir
defp load_players_async(socket) do
  %{page: page, sort_by: sort_by, sort_order: sort_order} = socket.assigns

  start_async(socket, :load_players, fn ->
    BuxBoosterStats.get_all_player_stats(
      page: page,
      per_page: @per_page,
      sort_by: sort_by,
      sort_order: sort_order
    )
  end)
end
```

---

#### STEP 12: Update Index LiveView

**File:** `lib/blockster_v2_web/live/admin/stats_live/index.ex`

Verify it uses `BuxBoosterStats.get_player_count()`:

```elixir
# In mount or wherever player count is fetched:
player_count = BuxBoosterStats.get_player_count()
```

---

#### STEP 13: Restart Nodes and Create Table

After making all code changes, restart both nodes to create the new Mnesia table:

```bash
# Terminal 1 - Stop node1, then restart
# Ctrl+C twice to stop
elixir --sname node1 -S mix phx.server

# Terminal 2 - Stop node2, then restart
# Ctrl+C twice to stop
PORT=4001 elixir --sname node2 -S mix phx.server
```

**Verify table was created:**
```elixir
# In IEx on node1:
:mnesia.table_info(:user_betting_stats, :size)
# Should return 0 (empty table)
```

---

#### STEP 14: Run Backfill

After nodes are running with the new table:

```elixir
# In IEx on node1:
BlocksterV2.BuxBoosterStats.Backfill.run()

# Expected output:
# [Backfill] Starting user_betting_stats backfill...
# [Backfill] Found 1,234 users in PostgreSQL
# [Backfill] Found 567 settled games in Mnesia
# [Backfill] Complete!
# [Backfill]   - 89 users with betting history
# [Backfill]   - 1,145 users with zero bets
# [Backfill]   - 1,234 total records created
```

**Verify backfill:**
```elixir
# Check record count matches user count:
:mnesia.table_info(:user_betting_stats, :size)
# Should match number of users in PostgreSQL
```

---

#### STEP 15: Test

1. **Load players page:** `/admin/stats/players`
   - Should load instantly (no PostgreSQL queries)
   - Should show ALL users, sorted by betting volume

2. **Test sorting:**
   - Click each column header
   - Verify sort direction toggles (asc/desc)

3. **Test pagination:**
   - Navigate between pages
   - Verify page numbers are correct

4. **Test real-time update:**
   - Place a test bet on `/play`
   - After settlement, refresh players page
   - Verify user's stats updated

---

#### Summary Checklist

- [ ] Delete `player_index.ex`, `indexer.ex`, `cache.ex`
- [ ] Remove Indexer/Cache from application.ex supervision tree
- [ ] Remove `:bux_booster_players` from MnesiaInitializer
- [ ] Add `:user_betting_stats` table to MnesiaInitializer
- [ ] Add `create_user_betting_stats/2` to Accounts
- [ ] Call `create_user_betting_stats` on user signup
- [ ] Create `backfill.ex` module
- [ ] Add `update_user_betting_stats/5` to BuxBoosterOnchain
- [ ] Call `update_user_betting_stats` from `settle_game/1`
- [ ] Rewrite `get_all_player_stats/1` in BuxBoosterStats
- [ ] Update `get_player_count/0` in BuxBoosterStats
- [ ] Remove PlayerIndex/Cache dependencies from BuxBoosterStats
- [ ] Verify Players LiveView uses new functions
- [ ] Verify Index LiveView uses new functions
- [ ] Restart both nodes
- [ ] Run backfill
- [ ] Test players page loads instantly
- [ ] Test sorting works
- [ ] Test pagination works
- [ ] Test real-time stats update on bet settlement

### 10.10 Benefits of This Approach

| Before | After |
|--------|-------|
| Blockchain event scanning | Direct Mnesia queries |
| On-chain queries per player | Pre-computed stats in Mnesia |
| Complex caching with TTL | Real-time updates on settlement |
| Only players who have bet | All users shown |
| Multiple GenServers | Single Mnesia table |
| Slow page loads | Instant page loads |

---

## Appendix A: Adding Per-Difficulty Stats for ROGUE Betting

### A.1 Current State

**BUX** has full per-difficulty tracking via the V7 contract upgrade:
- `BuxPlayerStats.betsPerDifficulty[9]` - count of bets at each difficulty level
- `BuxPlayerStats.profitLossPerDifficulty[9]` - P/L at each difficulty level
- Accessed via `BuxBoosterGame.getBuxPlayerStats(address)`

**ROGUE** currently tracks only aggregate stats in ROGUEBankroll:
```solidity
struct BuxBoosterPlayerStats {
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 totalWagered;
    uint256 totalWinnings;
    uint256 totalLosses;
}
```

**Missing for ROGUE:**
- `betsPerDifficulty[9]` - count of bets at each difficulty level
- `profitLossPerDifficulty[9]` - P/L at each difficulty level

### A.2 Smart Contract Changes Required

#### A.2.1 Update ROGUEBankroll Contract

**File**: `contracts/bux-booster-game/contracts/ROGUEBankroll.sol`

1. **Add new struct** (or modify existing - must add fields at END for storage compatibility):

```solidity
// Option 1: Modify existing struct (APPEND ONLY!)
struct BuxBoosterPlayerStats {
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 totalWagered;
    uint256 totalWinnings;
    uint256 totalLosses;
    // NEW FIELDS - must be at end
    uint256[9] betsPerDifficulty;      // Count of bets at each difficulty
    int256[9] profitLossPerDifficulty; // P/L at each difficulty
}
```

2. **Update `_processBuxBoosterWin()` function** (~line 1760-1800):

```solidity
function _processBuxBoosterWin(
    address winner, 
    uint256 amount, 
    uint256 payout,
    int8 difficulty  // ADD THIS PARAMETER
) internal {
    // ... existing code ...
    
    BuxBoosterPlayerStats storage stats = buxBoosterPlayerStats[winner];
    stats.totalBets++;
    stats.wins++;
    stats.totalWagered += amount;
    stats.totalWinnings += (payout - amount);
    
    // NEW: Per-difficulty tracking
    uint256 diffIndex = uint256(int256(difficulty) + 4);  // -4 to 4 -> 0 to 8
    stats.betsPerDifficulty[diffIndex]++;
    int256 profit = int256(payout) - int256(amount);
    stats.profitLossPerDifficulty[diffIndex] += profit;
    
    // ... rest of existing code ...
}
```

3. **Update `_processBuxBoosterLoss()` function** (~line 1810-1850):

```solidity
function _processBuxBoosterLoss(
    address player, 
    uint256 amount,
    int8 difficulty  // ADD THIS PARAMETER
) internal {
    // ... existing code ...
    
    BuxBoosterPlayerStats storage stats = buxBoosterPlayerStats[player];
    stats.totalBets++;
    stats.losses++;
    stats.totalWagered += amount;
    stats.totalLosses += amount;
    
    // NEW: Per-difficulty tracking
    uint256 diffIndex = uint256(int256(difficulty) + 4);  // -4 to 4 -> 0 to 8
    stats.betsPerDifficulty[diffIndex]++;
    stats.profitLossPerDifficulty[diffIndex] -= int256(amount);
    
    // ... rest of existing code ...
}
```

4. **Update the external caller interfaces** - BuxBoosterGame needs to pass difficulty to ROGUEBankroll:

```solidity
// In ROGUEBankroll - update interface
function recordBuxBoosterWin(address winner, uint256 amount, uint256 payout, int8 difficulty) external;
function recordBuxBoosterLoss(address player, uint256 amount, int8 difficulty) external;
```

5. **Add view function for querying** (similar to BuxBoosterGame.getBuxPlayerStats):

```solidity
function getBuxBoosterPlayerStats(address player) external view returns (
    uint256 totalBets,
    uint256 wins,
    uint256 losses,
    uint256 totalWagered,
    uint256 totalWinnings,
    uint256 totalLosses,
    uint256[9] memory betsPerDifficulty,
    int256[9] memory profitLossPerDifficulty
) {
    BuxBoosterPlayerStats storage stats = buxBoosterPlayerStats[player];
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
```

#### A.2.2 Update BuxBoosterGame Contract

**File**: `contracts/bux-booster-game/contracts/BuxBoosterGame.sol`

1. **Update `settleBetROGUE()` to pass difficulty to ROGUEBankroll**:

The current `settleBetROGUE()` calls internal helpers that call ROGUEBankroll. Update `_callBankrollWinning()` and `_callBankrollLosing()` to include difficulty:

```solidity
// Update helper function signatures
function _callBankrollWinning(address player, uint256 amount, uint256 payout, int8 difficulty) internal;
function _callBankrollLosing(address player, uint256 amount, int8 difficulty) internal;
```

### A.3 Backend Changes Required

#### A.3.1 Update BuxBoosterStats Module

**File**: `lib/blockster_v2/bux_booster_stats.ex`

1. **Add new function selector**:

```elixir
# Add to module attributes
@get_buxbooster_player_stats_selector "0x????????"  # Calculate from function signature
```

2. **Add getter function**:

```elixir
@doc """
Get per-difficulty ROGUE stats for a player from ROGUEBankroll.
Returns betsPerDifficulty and profitLossPerDifficulty arrays.
"""
def get_rogue_player_difficulty_stats(wallet_address) do
  # Similar to get_bux_player_stats but calls ROGUEBankroll.getBuxBoosterPlayerStats
  # Decode the response including the two new arrays
end
```

3. **Update `get_rogue_player_stats/1`** to include per-difficulty data:

```elixir
def get_rogue_player_stats(wallet_address) do
  # Existing query + new difficulty stats
  # Merge results into single response map with:
  # - bets_per_difficulty: [9 integers]
  # - profit_loss_per_difficulty: [9 integers, two's complement for negatives]
end
```

#### A.3.2 Update Admin UI

**File**: `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex`

1. **Add ROGUE per-difficulty section** (similar to existing BUX section):

```heex
<!-- ROGUE Per-Difficulty Breakdown -->
<%= if @rogue_stats && @rogue_stats.bets_per_difficulty do %>
  <div class="bg-white rounded-lg shadow p-6 mt-6">
    <h2 class="text-lg font-haas_medium_65 mb-4">ROGUE Per-Difficulty Breakdown</h2>
    <table class="w-full">
      <!-- Same structure as BUX table -->
    </table>
  </div>
<% end %>
```

2. **Remove or update the note** that says "ROGUE does not track per-difficulty stats on-chain"

### A.4 Deployment Steps

#### A.4.1 Contract Deployment

1. **Compile contracts**:
```bash
cd contracts/bux-booster-game
npx hardhat compile
```

2. **Deploy ROGUEBankroll upgrade** (V9 or whatever next version):
```bash
npx hardhat run scripts/upgrade-roguebankroll-v9.js --network rogueMainnet
```

3. **Deploy BuxBoosterGame upgrade** (V8 or whatever next version):
```bash
npx hardhat run scripts/upgrade-buxbooster-v8.js --network rogueMainnet
```

4. **Call initializers if needed** (for any new storage variables requiring initialization)

5. **Verify contracts on Roguescan**

#### A.4.2 Backend Deployment

1. **Update function selectors** - Calculate new selector for `getBuxBoosterPlayerStats(address)`:
```bash
# Function signature: getBuxBoosterPlayerStats(address)
# keccak256 hash first 4 bytes = selector
```

2. **Test locally** with both nodes running

3. **Deploy to Fly.io**:
```bash
flyctl deploy --app blockster-v2
```

### A.5 Important Considerations

#### A.5.1 Storage Layout Compatibility

**CRITICAL**: When modifying `BuxBoosterPlayerStats` struct:
- NEVER remove existing fields
- NEVER reorder existing fields
- ONLY add new fields at the END

The struct currently has 6 fields. Adding `betsPerDifficulty[9]` and `profitLossPerDifficulty[9]` is safe as long as they're appended.

#### A.5.2 Historical Data

**Problem**: Existing ROGUE bets (placed before this upgrade) won't have per-difficulty data populated.

**Options**:
1. **Accept incomplete history** - New bets will have data, old bets show zeros
2. **Backfill via events** - Parse historical `BuxBoosterBetPlaced` and `BuxBoosterWinningPayout` events to reconstruct per-difficulty stats (complex, gas-intensive if done on-chain)
3. **Off-chain backfill** - Query events and store reconstructed stats in Mnesia/Postgres (recommended)

#### A.5.3 Gas Cost Increase

Adding per-difficulty tracking increases gas cost per settlement:
- 2 SSTORE operations for array updates (~5,000 gas each for non-zero to non-zero)
- Estimated increase: ~10,000-20,000 gas per settlement

This is acceptable given current ROGUE gas costs.

### A.6 Timeline Estimate

| Task | Estimate |
|------|----------|
| ROGUEBankroll contract changes | 2-3 hours |
| BuxBoosterGame contract changes | 1-2 hours |
| Contract testing (unit + integration) | 2-3 hours |
| Backend stats module update | 1-2 hours |
| Admin UI update | 1 hour |
| End-to-end testing | 1-2 hours |
| Deployment + verification | 1 hour |
| **Total** | **9-14 hours** |

### A.7 Function Selector Calculation

To calculate the selector for the new ROGUEBankroll view function:

```javascript
const ethers = require('ethers');

// Function signature (no spaces, no parameter names)
const sig = 'getBuxBoosterPlayerStats(address)';
const selector = ethers.id(sig).slice(0, 10);
console.log(selector);  // e.g., 0x12345678
```

Or use cast:
```bash
cast sig 'getBuxBoosterPlayerStats(address)'
```

### A.8 Checklist (COMPLETED - Feb 4, 2026)

- [x] Update ROGUEBankroll.BuxBoosterPlayerStats struct (append fields)
- [x] Update ROGUEBankroll._processBuxBoosterWin() to track difficulty
- [x] Update ROGUEBankroll._processBuxBoosterLoss() to track difficulty
- [x] Add ROGUEBankroll.getBuxBoosterPlayerStats() view function
- [x] Update BuxBoosterGame to pass difficulty to ROGUEBankroll calls
- [x] Write contract upgrade script
- [x] Write contract tests
- [x] Deploy and verify contracts
- [x] Calculate new function selector
- [x] Update BuxBoosterStats module with new selector and decoder
- [x] Update get_rogue_player_stats/1 to include difficulty data
- [x] Update player_detail.ex UI to show ROGUE per-difficulty stats
- [x] Remove "ROGUE does not track per-difficulty stats" note
- [x] Test full flow locally
- [ ] Deploy backend to Fly.io
- [ ] Verify in production

### A.9 Deployment Record (Feb 4, 2026)

**ROGUEBankroll V9 Deployment**:
- **Proxy Address**: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
- **New Implementation**: `0x064630f3F3bB17e76449fD90Aa5C2eB71976c327`
- **Upgrade Script**: `contracts/bux-booster-game/scripts/upgrade-roguebankroll-v9.js`

**New Storage Variables**:
- `buxBoosterBetsPerDifficulty` - mapping(address => uint256[9])
- `buxBoosterPnLPerDifficulty` - mapping(address => int256[9])

**New View Function**:
- `getBuxBoosterPlayerStats(address)` - selector: `0x75db583f`
- Returns: (totalBets, wins, losses, totalWagered, totalWinnings, totalLosses, betsPerDifficulty[9], pnlPerDifficulty[9])

**Stack Too Deep Fix**:
- Added `_updatePerDifficultyStats(address, int8, int256)` helper function
- Extracted per-difficulty update logic from `settleBuxBoosterWinningBet()` and `settleBuxBoosterLosingBet()`

**Note**: Historical ROGUE bets (before this upgrade) won't have per-difficulty data - only new bets are tracked.

### A.10 ROGUEBankroll V10 Deployment (Feb 4, 2026)

**ROGUEBankroll V10 Deployment**:
- **Proxy Address**: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
- **Previous Implementation**: `0x064630f3F3bB17e76449fD90Aa5C2eB71976c327`
- **New Implementation**: `0xB8323C89c2730dffb322CF35dcf3Ce7dC45e16E2`
- **Upgrade Script**: `contracts/bux-booster-game/scripts/upgrade-roguebankroll-v10.js`

**Bug Fix - Per-Difficulty Index Calculation**:
The `_updatePerDifficultyStats()` function was using wrong index formula for positive difficulties (Win All modes).

```solidity
// V9 (WRONG for positive difficulties):
uint256 diffIndex = uint256(int256(difficulty) + 4);
// Result: difficulty 1 → index 5, difficulty 2 → index 6, etc. (off by 1)

// V10 (CORRECT - matches BuxBoosterGame):
uint256 diffIndex = difficulty < 0
    ? uint256(int256(difficulty) + 4)   // -4 to -1 → 0 to 3
    : uint256(int256(difficulty) + 3);  // 1 to 5 → 4 to 8
```

**Difficulty Index Mapping**:
| Contract Difficulty | Game Mode | Correct Index |
|---------------------|-----------|---------------|
| -4 | Win One 5-flip (1.02x) | 0 |
| -3 | Win One 4-flip (1.05x) | 1 |
| -2 | Win One 3-flip (1.13x) | 2 |
| -1 | Win One 2-flip (1.32x) | 3 |
| 1 | Single Flip (1.98x) | 4 |
| 2 | Win All 2-flip (3.96x) | 5 |
| 3 | Win All 3-flip (7.92x) | 6 |
| 4 | Win All 4-flip (15.84x) | 7 |
| 5 | Win All 5-flip (31.68x) | 8 |

**Note**: Historical per-difficulty data for positive difficulties (Win All modes) will be at wrong indices. This fix only affects new bets going forward.
