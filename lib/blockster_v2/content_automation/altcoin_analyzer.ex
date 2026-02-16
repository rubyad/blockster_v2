defmodule BlocksterV2.ContentAutomation.AltcoinAnalyzer do
  @moduledoc """
  Analyzes CoinGecko market data to identify trending altcoins,
  narrative rotations, and market movements for content generation.

  Makes its own CoinGecko API call (coins/markets) for richer data (7d/30d changes)
  and caches in ETS with 10-minute TTL. Falls back to PriceTracker's 24h data
  if the CoinGecko call fails.

  Does NOT modify PriceTracker or the token_prices Mnesia table.
  """

  require Logger

  alias BlocksterV2.ContentAutomation.FeedStore

  @cache_table :altcoin_analyzer_cache
  @cache_ttl_ms :timer.minutes(10)

  @coingecko_markets_url "https://api.coingecko.com/api/v3/coins/markets"

  # Sector tags — only symbols that PriceTracker actually tracks (41 tokens)
  @sector_tags %{
    "ai" => ~w(RENDER NEAR),
    "defi" => ~w(UNI AAVE),
    "l1" => ~w(SOL AVAX ADA DOT ATOM NEAR SUI APT),
    "l2" => ~w(ARB),
    "gaming" => ~w(),
    "rwa" => ~w(),
    "meme" => ~w(DOGE SHIB PEPE),
    "depin" => ~w(FIL RENDER)
  }

  # ── Public API ──

  @doc """
  Fetch enriched market data from CoinGecko (coins/markets endpoint).
  Cached in ETS with 10-minute TTL. Returns list of token maps with 7d/30d data.
  Falls back to PriceTracker 24h data if CoinGecko call fails.
  """
  def fetch_market_data do
    ensure_cache_table()

    case cached_get(:market_data) do
      {:ok, data} ->
        {:ok, data}

      :miss ->
        case fetch_from_coingecko() do
          {:ok, coins} ->
            cached_put(:market_data, coins)
            {:ok, coins}

          {:error, reason} ->
            Logger.warning("[AltcoinAnalyzer] CoinGecko call failed (#{inspect(reason)}), falling back to PriceTracker")
            {:ok, fallback_to_price_tracker()}
        end
    end
  end

  @doc """
  Get top N gainers and losers over a time period.
  Returns %{gainers: [...], losers: [...], period: period}
  """
  def get_movers(period \\ :"7d", limit \\ 10) do
    {:ok, coins} = fetch_market_data()

    sorted =
      coins
      |> Enum.filter(&has_period_data(&1, period))
      |> Enum.sort_by(&get_change(&1, period), :desc)

    gainers = Enum.take(sorted, limit)
    losers = sorted |> Enum.reverse() |> Enum.take(limit)

    %{gainers: gainers, losers: losers, period: period}
  end

  @doc """
  Detect narrative rotations — sectors where 3+ tokens move >5% in same direction.
  Returns list of {sector, %{tokens: [...], avg_change: float, count: int}}
  """
  def detect_narratives(period \\ :"7d") do
    {:ok, coins} = fetch_market_data()

    coins_by_symbol =
      coins
      |> Enum.map(fn coin -> {String.upcase(coin.symbol), coin} end)
      |> Map.new()

    @sector_tags
    |> Enum.map(fn {sector, symbols} ->
      tokens =
        symbols
        |> Enum.filter(&Map.has_key?(coins_by_symbol, &1))
        |> Enum.map(&Map.get(coins_by_symbol, &1))
        |> Enum.filter(&has_period_data(&1, period))

      avg_change = average_change(tokens, period)
      {sector, %{tokens: tokens, avg_change: avg_change, count: length(tokens)}}
    end)
    |> Enum.filter(fn {_sector, data} ->
      # Narrative = 3+ tokens moving in same direction by >5%
      data.count >= 3 and abs(data.avg_change) > 5.0
    end)
    |> Enum.sort_by(fn {_sector, data} -> abs(data.avg_change) end, :desc)
  end

  @doc """
  Format market data as structured text for Claude prompt.
  """
  def format_for_prompt(movers, narratives) do
    date_str = Calendar.strftime(DateTime.utc_now(), "%B %d, %Y")
    reference_prices = get_reference_prices()

    """
    MARKET DATA (from CoinGecko, #{date_str}):

    REFERENCE PRICES (use these exact values):
    #{reference_prices}

    TOP GAINERS (#{period_label(movers.period)}):
    #{format_token_list(movers.gainers, movers.period)}

    TOP LOSERS (#{period_label(movers.period)}):
    #{format_token_list(movers.losers, movers.period)}

    NARRATIVE ROTATIONS:
    #{format_narratives(narratives, movers.period)}
    """
  end

  @doc """
  Get recent news context from FeedStore for top mover tokens.
  Queries feed items and filters those whose titles mention any top mover name/symbol.
  """
  def get_recent_news_for_tokens(movers) do
    all_movers = (movers.gainers ++ movers.losers) |> Enum.uniq_by(& &1.symbol)

    # Collect search terms: both symbol and name for each mover
    search_terms =
      all_movers
      |> Enum.flat_map(fn coin ->
        [String.upcase(coin.symbol), String.downcase(coin.name)]
      end)

    # Get recent feed items (last 50)
    items = FeedStore.get_recent_feed_items(per_page: 100)

    # Filter items whose title mentions any mover
    matching =
      items
      |> Enum.filter(fn item ->
        title_lower = String.downcase(item.title || "")
        Enum.any?(search_terms, fn term ->
          String.contains?(title_lower, String.downcase(term))
        end)
      end)
      |> Enum.take(15)

    if matching == [] do
      "No recent news found matching top movers."
    else
      matching
      |> Enum.map(fn item ->
        url_part = if item.url, do: " (#{item.url})", else: ""
        "- [#{item.source}] #{item.title}#{url_part}"
      end)
      |> Enum.join("\n")
    end
  end

  @doc "Get sector tags map."
  def sector_tags, do: @sector_tags

  @doc "Get sector names list."
  def sector_names, do: Map.keys(@sector_tags) |> Enum.sort()

  @doc """
  Get data for a specific sector. Returns sector tokens with their market data.
  """
  def get_sector_data(sector, period \\ :"7d") do
    {:ok, coins} = fetch_market_data()

    symbols = Map.get(@sector_tags, sector, [])

    coins_by_symbol =
      coins
      |> Enum.map(fn coin -> {String.upcase(coin.symbol), coin} end)
      |> Map.new()

    tokens =
      symbols
      |> Enum.filter(&Map.has_key?(coins_by_symbol, &1))
      |> Enum.map(&Map.get(coins_by_symbol, &1))
      |> Enum.filter(&has_period_data(&1, period))
      |> Enum.sort_by(&get_change(&1, period), :desc)

    avg_change = average_change(tokens, period)
    direction = if avg_change >= 0, do: "up", else: "down"

    %{
      sector: sector,
      tokens: tokens,
      avg_change: avg_change,
      direction: direction,
      count: length(tokens),
      period: period
    }
  end

  # ── Private: CoinGecko API ──

  defp fetch_from_coingecko do
    url = "#{@coingecko_markets_url}?vs_currency=usd&order=market_cap_desc&per_page=100&page=1&price_change_percentage=7d,30d"

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        coins =
          body
          |> Enum.map(fn coin ->
            %{
              id: coin["id"],
              symbol: coin["symbol"] |> to_string() |> String.upcase(),
              name: coin["name"],
              current_price: coin["current_price"],
              market_cap: coin["market_cap"],
              total_volume: coin["total_volume"],
              price_change_24h: coin["price_change_percentage_24h"],
              price_change_7d: coin["price_change_percentage_7d_in_currency"],
              price_change_30d: coin["price_change_percentage_30d_in_currency"],
              last_updated: coin["last_updated"]
            }
          end)

        {:ok, coins}

      {:ok, %Req.Response{status: 429}} ->
        Logger.warning("[AltcoinAnalyzer] Rate limited by CoinGecko")
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fallback_to_price_tracker do
    BlocksterV2.PriceTracker.get_all_prices()
    |> Enum.map(fn {symbol, data} ->
      %{
        id: data.token_id,
        symbol: symbol,
        name: symbol,
        current_price: data.usd_price,
        market_cap: nil,
        total_volume: nil,
        price_change_24h: data.usd_24h_change,
        price_change_7d: nil,
        price_change_30d: nil,
        last_updated: data.last_updated
      }
    end)
  end

  # ── Private: Data Helpers ──

  defp has_period_data(coin, :"24h"), do: coin.price_change_24h != nil
  defp has_period_data(coin, :"7d"), do: coin.price_change_7d != nil
  defp has_period_data(coin, :"30d"), do: coin.price_change_30d != nil

  defp get_change(coin, :"24h"), do: coin.price_change_24h || 0.0
  defp get_change(coin, :"7d"), do: coin.price_change_7d || 0.0
  defp get_change(coin, :"30d"), do: coin.price_change_30d || 0.0

  defp average_change([], _period), do: 0.0

  defp average_change(tokens, period) do
    changes = Enum.map(tokens, &get_change(&1, period))
    Enum.sum(changes) / length(changes)
  end

  defp period_label(:"24h"), do: "24h"
  defp period_label(:"7d"), do: "7-day"
  defp period_label(:"30d"), do: "30-day"

  defp format_token_list([], _period), do: "  (none)"

  defp format_token_list(tokens, period) do
    tokens
    |> Enum.with_index(1)
    |> Enum.map(fn {coin, i} ->
      change = get_change(coin, period)
      price_str = format_price(coin.current_price)
      mcap_str = if coin.market_cap, do: " | MCap: $#{format_large_number(coin.market_cap)}", else: ""
      vol_str = if coin.total_volume, do: " | Vol: $#{format_large_number(coin.total_volume)}", else: ""

      "  #{i}. #{coin.symbol} (#{coin.name}): #{sign(change)}#{Float.round(change * 1.0, 2)}% | Price: $#{price_str}#{mcap_str}#{vol_str}"
    end)
    |> Enum.join("\n")
  end

  defp format_narratives([], _period), do: "  No clear narrative rotations detected."

  defp format_narratives(narratives, period) do
    narratives
    |> Enum.map(fn {sector, data} ->
      tokens = data.tokens |> Enum.map(& &1.symbol) |> Enum.join(", ")
      direction = if data.avg_change >= 0, do: "UP", else: "DOWN"
      change = Float.round(abs(data.avg_change) * 1.0, 2)

      "  #{String.upcase(sector)} sector #{direction}: avg #{sign(data.avg_change)}#{change}% (#{period_label(period)}) — #{tokens}"
    end)
    |> Enum.join("\n")
  end

  # Always include BTC and ETH prices so the LLM never has to guess them
  defp get_reference_prices do
    {:ok, coins} = fetch_market_data()

    reference_symbols = ~w(BTC ETH SOL BNB XRP)
    coins_by_symbol = coins |> Enum.map(fn c -> {String.upcase(c.symbol), c} end) |> Map.new()

    reference_symbols
    |> Enum.filter(&Map.has_key?(coins_by_symbol, &1))
    |> Enum.map(fn sym ->
      coin = Map.get(coins_by_symbol, sym)
      price_str = format_price(coin.current_price)
      change_24h = if coin.price_change_24h, do: "#{sign(coin.price_change_24h)}#{Float.round(coin.price_change_24h * 1.0, 2)}% (24h)", else: ""
      change_7d = if coin.price_change_7d, do: " | #{sign(coin.price_change_7d)}#{Float.round(coin.price_change_7d * 1.0, 2)}% (7d)", else: ""
      "  #{sym}: $#{price_str} #{change_24h}#{change_7d}"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "  (no reference price data available — do NOT guess prices)"
      data -> data
    end
  end

  defp sign(n) when n >= 0, do: "+"
  defp sign(_), do: ""

  defp format_price(nil), do: "N/A"
  defp format_price(price) when price >= 1, do: :erlang.float_to_binary(price * 1.0, decimals: 2)
  defp format_price(price) when price >= 0.01, do: :erlang.float_to_binary(price * 1.0, decimals: 4)
  defp format_price(price), do: :erlang.float_to_binary(price * 1.0, decimals: 8)

  defp format_large_number(nil), do: "N/A"
  defp format_large_number(n) when n >= 1_000_000_000, do: "#{Float.round(n / 1_000_000_000, 2)}B"
  defp format_large_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 2)}M"
  defp format_large_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_large_number(n), do: "#{n}"

  # ── Private: ETS Cache ──

  defp ensure_cache_table do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
    end
  rescue
    ArgumentError -> :ok
  end

  defp cached_get(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cached_put(key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {key, value, expires_at})
  rescue
    ArgumentError -> :ok
  end
end
