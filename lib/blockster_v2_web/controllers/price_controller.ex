defmodule BlocksterV2Web.PriceController do
  @moduledoc """
  Public API endpoint for token prices.
  Exposes cached prices from PriceTracker (which polls CoinGecko every 10 min).

  Used by high-rollers-nfts app to fetch ROGUE/ETH prices for USD value displays
  and APY calculations.
  """
  use BlocksterV2Web, :controller

  alias BlocksterV2.PriceTracker

  @doc """
  GET /api/prices/:symbol
  Returns the current USD price for a token symbol (e.g., ROGUE, ETH, BTC).

  Response:
    {
      "symbol": "ROGUE",
      "usd_price": 0.0000821,
      "usd_24h_change": 1.23,
      "last_updated": 1736100000
    }
  """
  def show(conn, %{"symbol" => symbol}) do
    symbol_upper = String.upcase(symbol)

    case PriceTracker.get_price(symbol_upper) do
      {:ok, price_data} ->
        json(conn, %{
          symbol: price_data.symbol,
          usd_price: price_data.usd_price,
          usd_24h_change: price_data.usd_24h_change,
          last_updated: price_data.last_updated
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found", symbol: symbol_upper})
    end
  end

  @doc """
  GET /api/prices
  Returns all cached token prices.

  Response:
    {
      "prices": {
        "ROGUE": {"usd_price": 0.0000821, "usd_24h_change": 1.23, ...},
        "ETH": {"usd_price": 3500.50, "usd_24h_change": -0.5, ...},
        ...
      },
      "count": 41
    }
  """
  def index(conn, _params) do
    prices = PriceTracker.get_all_prices()

    json(conn, %{
      prices: prices,
      count: map_size(prices)
    })
  end
end
