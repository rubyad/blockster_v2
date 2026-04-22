defmodule BlocksterV2.Shop.Pricing do
  @moduledoc """
  Shop-side pricing helpers. USD is the storage currency on products; SOL is
  the display + payment currency. This module provides the USD → SOL
  conversion using the cached PriceTracker feed.
  """

  alias BlocksterV2.PriceTracker

  # Reasonable fallback so the shop still renders pricing even if the rate
  # feed is momentarily unavailable. Orders are priced at signature time, so
  # this fallback only ever affects display, not charged amounts.
  @fallback_sol_usd 150.0

  @doc """
  Current SOL/USD rate. Returns a float; falls back to a safe default when
  the PriceTracker cache has no entry yet.
  """
  def sol_usd_rate do
    case PriceTracker.get_price("SOL") do
      {:ok, %{usd_price: price}} when is_number(price) and price > 0 -> price * 1.0
      _ -> @fallback_sol_usd
    end
  end

  @doc """
  Converts a USD price (float) into SOL using the given (or cached) rate.
  Returns a float.
  """
  def usd_to_sol(usd, rate \\ nil)
  def usd_to_sol(nil, _), do: 0.0
  def usd_to_sol(usd, nil), do: usd_to_sol(usd, sol_usd_rate())
  def usd_to_sol(usd, rate) when is_number(usd) and is_number(rate) and rate > 0, do: usd / rate
  def usd_to_sol(_, _), do: 0.0

  @doc """
  Formats a SOL amount for display. Uses more precision for small values so
  a $10 item doesn't show as "0.06 SOL" and round to zero.
  """
  def format_sol(sol) when is_number(sol) and sol >= 1,
    do: :erlang.float_to_binary(sol / 1.0, decimals: 2)

  def format_sol(sol) when is_number(sol) and sol >= 0.01,
    do: :erlang.float_to_binary(sol / 1.0, decimals: 3)

  def format_sol(sol) when is_number(sol), do: :erlang.float_to_binary(sol / 1.0, decimals: 4)
  def format_sol(_), do: "0.00"

  @doc """
  Formats a USD amount for display. Two decimals, leading dollar sign.
  """
  def format_usd(usd) when is_number(usd),
    do: "$" <> :erlang.float_to_binary(usd / 1.0, decimals: 2)

  def format_usd(_), do: "$0.00"
end
