defmodule BlocksterV2.PriceTracker do
  @moduledoc """
  GenServer that polls CoinGecko API every 10 minutes for cryptocurrency prices
  and stores them in Mnesia. Broadcasts price updates via PubSub.

  Tracks 41 tokens: ROGUE + top 40 by market cap.
  All tokens fetched in a single API call (under 50 token limit).
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
    # Use GlobalSingleton to avoid killing existing process during name conflicts
    # This prevents crashes during rolling deploys when Mnesia tables are being copied
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        # Notify the process that it's the globally registered instance
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        # Another node already started the global GenServer - this is expected
        :ignore
    end
  end

  @doc "Get current price for a token symbol (e.g., 'ROGUE', 'ETH', 'BTC')"
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

  @doc "Get all cached prices as a map keyed by symbol"
  def get_all_prices do
    :mnesia.dirty_match_object({:token_prices, :_, :_, :_, :_, :_})
    |> Enum.map(fn {:token_prices, id, symbol, price, change, updated} ->
      {symbol, %{
        token_id: id,
        symbol: symbol,
        usd_price: price,
        usd_24h_change: change,
        last_updated: updated
      }}
    end)
    |> Map.new()
  end

  @doc "Force refresh prices (for manual trigger)"
  def refresh_prices do
    GenServer.cast({:global, __MODULE__}, :fetch_prices)
  end

  @doc "Get the list of tracked token symbols"
  def tracked_symbols do
    Map.values(@tracked_tokens)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    # Don't start work here - wait for :registered message from start_link
    # This prevents duplicate work when GlobalSingleton loses the registration race
    {:ok, %{last_fetch: nil, fetch_count: 0, mnesia_ready: false, registered: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    # Now we're confirmed as the globally registered instance - start the Mnesia wait loop
    Process.send_after(self(), :wait_for_mnesia, 1000)
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    # Already registered, ignore duplicate
    {:noreply, state}
  end

  @impl true
  def handle_info(:wait_for_mnesia, %{mnesia_wait_attempts: attempts} = state) when attempts > 30 do
    # After 60 seconds of waiting, give up to avoid infinite loop
    Logger.error("[PriceTracker] Gave up waiting for Mnesia token_prices table after 60 seconds")
    {:noreply, state}
  end

  def handle_info(:wait_for_mnesia, state) do
    attempts = Map.get(state, :mnesia_wait_attempts, 0)

    # First check if we're still the global owner - another node might have started first
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        # We are the global owner - proceed with initialization
        if table_ready?(:token_prices) do
          Logger.info("[PriceTracker] Mnesia table ready, starting price fetcher")
          send(self(), :fetch_prices)
          {:noreply, %{state | mnesia_ready: true}}
        else
          Logger.info("[PriceTracker] Waiting for Mnesia token_prices table... (attempt #{attempts + 1})")
          Process.send_after(self(), :wait_for_mnesia, 2000)
          {:noreply, Map.put(state, :mnesia_wait_attempts, attempts + 1)}
        end

      other_pid ->
        # Another node became the global owner - stop this instance
        Logger.info("[PriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
        {:stop, :normal, state}
    end
  end

  # Check if table is ready for use - handles both local and remote table copies
  defp table_ready?(table_name) do
    # First check if table exists in the schema at all
    tables = :mnesia.system_info(:tables)

    if table_name in tables do
      # Table exists in schema, now check if it's accessible
      # Use wait_for_tables with a short timeout to verify it's usable
      case :mnesia.wait_for_tables([table_name], 1000) do
        :ok -> true
        {:timeout, _} -> false
        {:error, _} -> false
      end
    else
      false
    end
  catch
    :exit, _ -> false
  end

  @impl true
  def handle_info(:fetch_prices, state) do
    # Check if we're still the global owner - another node might have taken over
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        fetch_and_store_prices()
        schedule_next_fetch()
        {:noreply, %{state | last_fetch: System.system_time(:second), fetch_count: state.fetch_count + 1}}

      other_pid ->
        # Another node is now the global owner - stop this instance
        Logger.info("[PriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:fetch_prices, state) do
    # Check if we're still the global owner
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        fetch_and_store_prices()
        {:noreply, %{state | last_fetch: System.system_time(:second), fetch_count: state.fetch_count + 1}}

      _other_pid ->
        # Not the owner, ignore
        {:noreply, state}
    end
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
        updated_count = store_prices(prices, now)
        Logger.info("[PriceTracker] Updated #{updated_count}/#{map_size(@tracked_tokens)} token prices")

        # Broadcast price updates to all subscribed LiveViews
        broadcast_price_update()

      {:error, reason} ->
        Logger.error("[PriceTracker] Failed to fetch prices: #{inspect(reason)}")
    end
  end

  defp store_prices(prices, now) do
    Enum.reduce(@tracked_tokens, 0, fn {token_id, symbol}, count ->
      case Map.get(prices, token_id) do
        %{"usd" => usd_price} = data ->
          usd_24h_change = Map.get(data, "usd_24h_change", 0.0) || 0.0

          record = {:token_prices, token_id, symbol, usd_price, usd_24h_change, now}
          :mnesia.dirty_write(record)

          count + 1

        nil ->
          # Token not found in response - might not be listed on CoinGecko
          count
      end
    end)
  end

  defp fetch_from_coingecko(url) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
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

  defp broadcast_price_update do
    prices = get_all_prices()
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      @pubsub_topic,
      {:token_prices_updated, prices}
    )
  end
end
