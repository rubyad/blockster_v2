defmodule HighRollers.PriceCache do
  @moduledoc """
  GenServer that polls BlocksterV2 API for ROGUE and ETH prices every minute.
  Stores prices in Mnesia (hr_prices table) for fast, synchronous access.

  Used by RevenuesLive and other pages that need price data for USD displays
  and APY calculations.

  On startup, fetches prices immediately so the cache is warm.
  """
  use GenServer
  require Logger

  @blockster_api_url "https://blockster-v2.fly.dev/api/prices"
  @poll_interval :timer.minutes(1)
  @symbols ["ROGUE", "ETH"]

  # Default prices used if API unavailable
  @default_prices %{
    "ROGUE" => 0.0001,
    "ETH" => 3000.0
  }

  # ===== Public API =====

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get a single price from cache (fast Mnesia read)"
  def get_price(symbol) do
    case :mnesia.dirty_read(:hr_prices, symbol) do
      [{:hr_prices, ^symbol, usd_price, _change, _updated_at}] ->
        usd_price

      [] ->
        Map.get(@default_prices, symbol, 0)
    end
  catch
    # Table doesn't exist yet (first run before server restart creates table)
    :exit, {:aborted, {:no_exists, _}} ->
      Map.get(@default_prices, symbol, 0)
  end

  @doc "Get ROGUE price from cache"
  def get_rogue_price, do: get_price("ROGUE")

  @doc "Get ETH price from cache"
  def get_eth_price, do: get_price("ETH")

  @doc "Calculate NFT value in ROGUE based on 0.32 ETH mint price and current prices"
  def get_nft_value_rogue do
    rogue_price = get_rogue_price()
    eth_price = get_eth_price()

    if rogue_price > 0 do
      nft_value_usd = 0.32 * eth_price
      nft_value_usd / rogue_price
    else
      9_600_000  # Default fallback if prices unavailable
    end
  end

  @doc "Force refresh prices now (for testing/debugging)"
  def refresh_now do
    GenServer.cast(__MODULE__, :fetch_prices)
  end

  # ===== GenServer Callbacks =====

  @impl true
  def init(_opts) do
    Logger.info("[PriceCache] Starting price cache")

    # Wait for Mnesia table to be ready
    :mnesia.wait_for_tables([:hr_prices], 10_000)

    # Fetch immediately on startup
    send(self(), :fetch_prices)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:fetch_prices, state) do
    fetch_and_store_prices()
    schedule_next_poll()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:fetch_prices, state) do
    fetch_and_store_prices()
    {:noreply, state}
  end

  # ===== Private Functions =====

  defp schedule_next_poll do
    Process.send_after(self(), :fetch_prices, @poll_interval)
  end

  defp fetch_and_store_prices do
    now = System.system_time(:second)

    Enum.each(@symbols, fn symbol ->
      case fetch_price_from_api(symbol) do
        {:ok, price_data} ->
          store_price(symbol, price_data, now)

        {:error, reason} ->
          Logger.warning("[PriceCache] Failed to fetch #{symbol} price: #{inspect(reason)}")
      end
    end)
  end

  defp fetch_price_from_api(symbol) do
    url = "#{@blockster_api_url}/#{symbol}"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"usd_price" => price} = body}} ->
        {:ok, %{
          usd_price: price,
          usd_24h_change: Map.get(body, "usd_24h_change")
        }}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Handle atom keys (Req may decode differently)
        {:ok, %{
          usd_price: Map.get(body, :usd_price, 0),
          usd_24h_change: Map.get(body, :usd_24h_change)
        }}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_price(symbol, %{usd_price: price, usd_24h_change: change}, timestamp) do
    record = {:hr_prices, symbol, price, change, timestamp}
    :mnesia.dirty_write(record)
    Logger.debug("[PriceCache] Updated #{symbol}: $#{price}")
  end
end
