# ROGUE Price Display Implementation Plan

## Status: ✅ IMPLEMENTED (Dec 31, 2024)

## Overview

Poll CoinGecko API every 10 minutes for cryptocurrency prices (41 tokens: ROGUE + top 40 by market cap), store all in Mnesia with a single API call, and display USD values in the BUX Booster game UI.

## Goals

1. ✅ Fetch and cache cryptocurrency prices from CoinGecko API
2. ✅ Display USD value below user's ROGUE balance in game UI
3. ✅ Display USD value below ROGUE house bankroll balance
4. ✅ Real-time updates via PubSub broadcasts when prices change

## USD Display Locations (All Implemented)

| Location | Description |
|----------|-------------|
| **User Balance** | Below ROGUE balance in bottom-left when betting |
| **House Bankroll** | Below house balance (linked to roguetrader.io/rogue-bankroll) |
| **Bet Input** | Right side of bet amount input field |
| **Potential Profit** | Right side of potential win amount |
| **Spinning Balance** | Below balance in bottom-left during coin animation |
| **Win Payout** | Below payout amount on win screen |
| **Loss Amount** | Below loss amount on loss screen |

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        CoinGecko API                            │
│              (Rate limit: 10-30 calls/min free tier)            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼ (every 10 minutes)
┌─────────────────────────────────────────────────────────────────┐
│                    PriceTracker GenServer                       │
│  - Polls CoinGecko API                                          │
│  - Stores prices in Mnesia                                      │
│  - Broadcasts price updates via PubSub                          │
└─────────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
       │   Mnesia    │  │   PubSub    │  │  LiveViews  │
       │ token_prices│  │  Broadcast  │  │  Subscribe  │
       └─────────────┘  └─────────────┘  └─────────────┘
```

---

## Implementation Steps

### Step 1: Create Mnesia Table for Token Prices

**File**: `lib/blockster_v2/mnesia_initializer.ex`

Add new table `token_prices` to store cached prices:

```elixir
# Table schema
# {:token_prices, token_id, symbol, usd_price, usd_24h_change, last_updated}
#
# Fields:
#   - token_id: CoinGecko ID (e.g., "rogue-chain", "ethereum")
#   - symbol: Token symbol (e.g., "ROGUE", "ETH")
#   - usd_price: Current USD price (float)
#   - usd_24h_change: 24h price change percentage (float)
#   - last_updated: Unix timestamp of last update (integer)

@token_prices_attributes [:token_id, :symbol, :usd_price, :usd_24h_change, :last_updated]

# In create_tables/0:
:mnesia.create_table(:token_prices,
  attributes: @token_prices_attributes,
  disc_copies: [node()],
  type: :set,
  index: [:symbol]  # Index by symbol for fast lookups
)
```

### Step 2: Create PriceTracker GenServer

**File**: `lib/blockster_v2/price_tracker.ex`

```elixir
defmodule BlocksterV2.PriceTracker do
  @moduledoc """
  GenServer that polls CoinGecko API every 10 minutes for cryptocurrency prices
  and stores them in Mnesia. Broadcasts price updates via PubSub.
  """
  use GenServer
  require Logger

  @poll_interval :timer.minutes(10)
  @pubsub_topic "token_prices"

  # CoinGecko token IDs - Top 40 by market cap + ROGUE
  # Updated from CoinGecko API (Dec 2024)
  # Excludes wrapped/staked/bridged variants (use base tokens)
  @tracked_tokens %{
    # Custom tokens
    "rogue" => "ROGUE",

    # Top 40 by market cap
    "bitcoin" => "BTC",
    "ethereum" => "ETH",
    "tether" => "USDT",
    "binancecoin" => "BNB",
    "ripple" => "XRP",
    "usd-coin" => "USDC",
    "solana" => "SOL",
    "tron" => "TRX",
    "dogecoin" => "DOGE",
    "cardano" => "ADA",
    "bitcoin-cash" => "BCH",
    "chainlink" => "LINK",
    "leo-token" => "LEO",
    "zcash" => "ZEC",
    "monero" => "XMR",
    "stellar" => "XLM",
    "hyperliquid" => "HYPE",
    "litecoin" => "LTC",
    "sui" => "SUI",
    "avalanche-2" => "AVAX",
    "hedera-hashgraph" => "HBAR",
    "dai" => "DAI",
    "shiba-inu" => "SHIB",
    "the-open-network" => "TON",
    "uniswap" => "UNI",
    "crypto-com-chain" => "CRO",
    "polkadot" => "DOT",
    "bitget-token" => "BGB",
    "near" => "NEAR",
    "pepe" => "PEPE",
    "aptos" => "APT",
    "internet-computer" => "ICP",
    "aave" => "AAVE",
    "kaspa" => "KAS",
    "ethereum-classic" => "ETC",
    "render-token" => "RENDER",
    "arbitrum" => "ARB",
    "vechain" => "VET",
    "filecoin" => "FIL",
    "cosmos" => "ATOM"
  }

  # CoinGecko API endpoint (free tier, no API key required)
  @coingecko_api "https://api.coingecko.com/api/v3"

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current price for a token symbol (e.g., 'ROGUE', 'ETH')"
  def get_price(symbol) do
    case :mnesia.dirty_index_read(:token_prices, symbol, :symbol) do
      [{:token_prices, _id, ^symbol, usd_price, usd_24h_change, last_updated}] ->
        {:ok, %{
          symbol: symbol,
          usd_price: usd_price,
          usd_24h_change: usd_24h_change,
          last_updated: last_updated
        }}
      [] ->
        {:error, :not_found}
    end
  end

  @doc "Get all cached prices"
  def get_all_prices do
    :mnesia.dirty_match_object({:token_prices, :_, :_, :_, :_, :_})
    |> Enum.map(fn {:token_prices, id, symbol, price, change, updated} ->
      %{
        token_id: id,
        symbol: symbol,
        usd_price: price,
        usd_24h_change: change,
        last_updated: updated
      }
    end)
  end

  @doc "Force refresh prices (for manual trigger)"
  def refresh_prices do
    GenServer.cast(__MODULE__, :fetch_prices)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    # Fetch prices immediately on startup
    send(self(), :fetch_prices)
    {:ok, %{last_fetch: nil}}
  end

  @impl true
  def handle_info(:fetch_prices, state) do
    fetch_and_store_prices()
    schedule_next_fetch()
    {:noreply, %{state | last_fetch: System.system_time(:second)}}
  end

  @impl true
  def handle_cast(:fetch_prices, state) do
    fetch_and_store_prices()
    {:noreply, %{state | last_fetch: System.system_time(:second)}}
  end

  # --- Private Functions ---

  defp schedule_next_fetch do
    Process.send_after(self(), :fetch_prices, @poll_interval)
  end

  defp fetch_and_store_prices do
    token_ids = @tracked_tokens |> Map.keys() |> Enum.join(",")

    url = "#{@coingecko_api}/simple/price?ids=#{token_ids}&vs_currencies=usd&include_24hr_change=true"

    case fetch_from_coingecko(url) do
      {:ok, prices} ->
        now = System.system_time(:second)

        Enum.each(@tracked_tokens, fn {token_id, symbol} ->
          case Map.get(prices, token_id) do
            %{"usd" => usd_price} = data ->
              usd_24h_change = Map.get(data, "usd_24h_change", 0.0)

              record = {:token_prices, token_id, symbol, usd_price, usd_24h_change, now}
              :mnesia.dirty_write(record)

              Logger.info("[PriceTracker] Updated #{symbol}: $#{usd_price} (#{format_change(usd_24h_change)})")

            nil ->
              Logger.warning("[PriceTracker] No price data for #{token_id} (#{symbol})")
          end
        end)

        # Broadcast price updates to all subscribed LiveViews
        broadcast_price_update()

      {:error, reason} ->
        Logger.error("[PriceTracker] Failed to fetch prices: #{inspect(reason)}")
    end
  end

  defp fetch_from_coingecko(url) do
    # Use Req or HTTPoison for HTTP requests
    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 429}} ->
        Logger.warning("[PriceTracker] Rate limited by CoinGecko")
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_change(change) when is_number(change) do
    sign = if change >= 0, do: "+", else: ""
    "#{sign}#{Float.round(change, 2)}%"
  end
  defp format_change(_), do: "0%"

  defp broadcast_price_update do
    prices = get_all_prices()
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      @pubsub_topic,
      {:token_prices_updated, prices}
    )
  end
end
```

### Step 3: Add PriceTracker to Supervision Tree

**File**: `lib/blockster_v2/application.ex`

```elixir
# In children list, after MnesiaInitializer:
{BlocksterV2.PriceTracker, []}
```

### Step 4: Create PriceTracker Hook for LiveViews

**File**: `lib/blockster_v2_web/live/price_tracker_hook.ex`

```elixir
defmodule BlocksterV2Web.PriceTrackerHook do
  @moduledoc """
  LiveView hook that subscribes to token price updates and maintains
  :token_prices assign with current USD prices.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
    end

    # Load initial prices from Mnesia
    prices = BlocksterV2.PriceTracker.get_all_prices()
    |> Enum.map(fn p -> {p.symbol, p} end)
    |> Map.new()

    socket = assign(socket, :token_prices, prices)

    {:cont, socket}
  end

  # Handle price update broadcasts
  def handle_info({:token_prices_updated, prices}, socket) do
    prices_map = prices
    |> Enum.map(fn p -> {p.symbol, p} end)
    |> Map.new()

    {:noreply, assign(socket, :token_prices, prices_map)}
  end
end
```

### Step 5: Update BuxBoosterLive to Display USD Values

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

#### 5a. Add hook attachment in mount:

```elixir
def mount(_params, _session, socket) do
  # Subscribe to price updates if connected
  if connected?(socket) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
  end

  # Load initial ROGUE price
  rogue_price = case BlocksterV2.PriceTracker.get_price("ROGUE") do
    {:ok, price_data} -> price_data.usd_price
    {:error, _} -> nil
  end

  socket
  |> assign(:rogue_usd_price, rogue_price)
  # ... rest of assigns
end
```

#### 5b. Add handle_info for price updates:

```elixir
def handle_info({:token_prices_updated, prices}, socket) do
  rogue_price = case Enum.find(prices, fn p -> p.symbol == "ROGUE" end) do
    %{usd_price: price} -> price
    nil -> socket.assigns.rogue_usd_price
  end

  {:noreply, assign(socket, :rogue_usd_price, rogue_price)}
end
```

#### 5c. Add helper function for USD formatting:

```elixir
defp format_usd(nil, _amount), do: nil
defp format_usd(price, amount) when is_number(price) and is_number(amount) do
  usd_value = price * amount
  cond do
    usd_value >= 1_000_000 -> "$#{Float.round(usd_value / 1_000_000, 2)}M"
    usd_value >= 1_000 -> "$#{Float.round(usd_value / 1_000, 2)}K"
    usd_value >= 1 -> "$#{Float.round(usd_value, 2)}"
    true -> "$#{Float.round(usd_value, 4)}"
  end
end
```

### Step 6: Update Template to Display USD Values

**File**: `lib/blockster_v2_web/live/bux_booster_live.html.heex`

#### 6a. Below ROGUE balance (user's balance):

```heex
<%= if @selected_token == "ROGUE" do %>
  <div class="text-center">
    <span class="text-lg font-bold">
      <%= Number.Delimit.number_to_delimited(@balances["ROGUE"] || 0, precision: 2) %> ROGUE
    </span>
    <%= if @rogue_usd_price do %>
      <div class="text-xs text-gray-500">
        ≈ <%= format_usd(@rogue_usd_price, @balances["ROGUE"] || 0) %>
      </div>
    <% end %>
  </div>
<% end %>
```

#### 6b. Below house bankroll balance:

```heex
<div class="text-sm text-gray-600">
  House: <%= Number.Delimit.number_to_delimited(@house_balance, precision: 2) %> <%= @selected_token %>
  <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
    <span class="text-xs text-gray-400">
      (≈ <%= format_usd(@rogue_usd_price, @house_balance) %>)
    </span>
  <% end %>
</div>
```

---

## CoinGecko API Details

### Endpoint Used

```
GET https://api.coingecko.com/api/v3/simple/price
  ?ids=rogue-chain,ethereum,tether,usd-coin,arbitrum
  &vs_currencies=usd
  &include_24hr_change=true
```

### Response Format

```json
{
  "bitcoin": {"usd": 94567.12, "usd_24h_change": 1.23},
  "ethereum": {"usd": 3456.78, "usd_24h_change": 2.34},
  "tether": {"usd": 1.0, "usd_24h_change": 0.01},
  "binancecoin": {"usd": 687.45, "usd_24h_change": -0.5},
  "ripple": {"usd": 2.18, "usd_24h_change": 3.2},
  "usd-coin": {"usd": 1.0, "usd_24h_change": 0.0},
  "solana": {"usd": 189.34, "usd_24h_change": 4.5},
  "rogue": {"usd": 0.0234, "usd_24h_change": -1.5},
  ... // 41 tokens total in one response
}
```

### Rate Limits (Free Tier)

- **30 calls per minute** (with Demo API key)
- **10,000 calls per month** (Demo tier)
- **50 tokens max per request** (we use 41)
- 10-minute polling = 6 calls/hour = **4,320 calls/month** (well within 10K limit)

---

## Mnesia Table Schema

### token_prices Table

| Index | Field | Type | Description |
|-------|-------|------|-------------|
| 0 | :token_prices | atom | Table name |
| 1 | token_id | string | CoinGecko ID (primary key) |
| 2 | symbol | string | Token symbol (indexed) |
| 3 | usd_price | float | Current USD price |
| 4 | usd_24h_change | float | 24h change percentage |
| 5 | last_updated | integer | Unix timestamp |

---

## PubSub Topics

| Topic | Message | Description |
|-------|---------|-------------|
| `token_prices` | `{:token_prices_updated, prices}` | Broadcast when prices refresh |

---

## Error Handling

### API Failures

- Log error, keep existing Mnesia data
- Retry on next scheduled poll (10 minutes)
- UI shows last known price (stale but better than nothing)

### Rate Limiting (429)

- Log warning
- Skip update, wait for next poll
- Consider exponential backoff if persistent

### Missing Token Data

- Log warning for missing token
- Other tokens still update normally
- UI shows nothing if price unavailable

---

## Testing

### Manual Testing

```elixir
# In IEx console:

# Force price refresh
BlocksterV2.PriceTracker.refresh_prices()

# Get ROGUE price
BlocksterV2.PriceTracker.get_price("ROGUE")

# Get all prices
BlocksterV2.PriceTracker.get_all_prices()

# Check Mnesia directly
:mnesia.dirty_match_object({:token_prices, :_, :_, :_, :_, :_})
```

### Verify UI Display

1. Navigate to /play
2. Select ROGUE token
3. Verify USD value appears below balance
4. Verify USD value appears below house bankroll
5. Wait 10 minutes, verify values update

---

## Files to Create/Modify

### New Files

1. `lib/blockster_v2/price_tracker.ex` - Main GenServer
2. `lib/blockster_v2_web/live/price_tracker_hook.ex` - LiveView hook (optional)

### Modified Files

1. `lib/blockster_v2/mnesia_initializer.ex` - Add token_prices table
2. `lib/blockster_v2/application.ex` - Add PriceTracker to supervision tree
3. `lib/blockster_v2_web/live/bux_booster_live.ex` - Subscribe to prices, add assigns
4. `lib/blockster_v2_web/live/bux_booster_live.html.heex` - Display USD values
5. `mix.exs` - Add `req` dependency if not present

---

## Dependencies

```elixir
# In mix.exs deps (if not already present):
{:req, "~> 0.4"}  # HTTP client
```

---

## Future Enhancements

1. **Price Alerts**: Notify users of significant price movements
2. **Historical Charts**: Store price history for mini charts
3. **Multiple Currencies**: Support EUR, GBP, etc.
4. **Price API Fallback**: Use multiple sources (CoinGecko, CoinMarketCap, DEX)
5. **Caching Layer**: Add ETS cache in front of Mnesia for faster reads
6. **Admin Dashboard**: View all prices, force refresh, configure tokens

---

## Deployment Notes

### After Deploying

1. Restart both nodes to create new Mnesia table
2. Verify PriceTracker starts and fetches prices
3. Check logs for successful price updates
4. Verify UI displays USD values

### Rollback

- Feature is additive (new table, new GenServer)
- Safe to deploy/rollback without data migration
- If CoinGecko unavailable, UI gracefully hides USD values
