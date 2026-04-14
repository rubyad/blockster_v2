defmodule BlocksterV2Web.Widgets.FsHeroHelpers do
  @moduledoc """
  Shared formatter + resolver helpers for the FateSwap hero widgets
  (`fs_hero_portrait`, `fs_hero_landscape`).

  Both hero widgets receive:

    * `banner` — the `ad_banner` row
    * `trades` — `FateSwapFeedTracker.get_trades/0` (recent settled orders)
    * `selection` — binary order id picked by `WidgetSelector`, or `nil`
    * `order_override` — optional full order map pushed by the hook on
      a selection-changed event; wins over the `trades` lookup

  The helpers resolve the current order and centralise the status
  pill, profit coloring, conviction bar position, and USD/SOL number
  formatters so the components themselves stay presentational.
  """

  @doc "Returns the order map the widget should render, or `nil` for empty state."
  def resolve_order(trades, selection, order_override \\ nil)

  def resolve_order(_trades, _selection, %{} = override) when map_size(override) > 0,
    do: override

  def resolve_order(trades, order_id, _) when is_binary(order_id) and is_list(trades) do
    Enum.find(trades, fn t -> t["id"] == order_id end) || List.first(trades)
  end

  def resolve_order(trades, _, _) when is_list(trades), do: List.first(trades)
  def resolve_order(_, _, _), do: nil

  # ── Status pill ───────────────────────────────────────────────────────────

  @doc """
  Returns `{label, class}` for the top status pill. The class is the
  Tailwind utilities to apply; label is the uppercase text (spaces in
  the source become non-breaking in the component template).
  """
  def status(%{"status_text" => "DISCOUNT FILLED"}),
    do: {"DISCOUNT FILLED", "bg-[#22C55E]/14 text-[#22C55E]"}

  def status(%{"status_text" => "ORDER FILLED"}),
    do: {"ORDER FILLED", "bg-[#22C55E]/14 text-[#22C55E]"}

  def status(%{"status_text" => "NOT FILLED"}),
    do: {"NOT FILLED", "bg-[#EF4444]/14 text-[#EF4444]"}

  def status(%{"filled" => true}), do: {"ORDER FILLED", "bg-[#22C55E]/14 text-[#22C55E]"}
  def status(_), do: {"NOT FILLED", "bg-[#EF4444]/14 text-[#EF4444]"}

  # ── Side + headline ───────────────────────────────────────────────────────

  def action_verb(%{"side" => "sell"}), do: "Sold"
  def action_verb(_), do: "Bought"

  def paid_label(%{"side" => "sell"}), do: "Trader Sold"
  def paid_label(_), do: "Trader Paid"

  def discount_kind(%{"side" => "sell"}), do: "premium"
  def discount_kind(_), do: "discount"

  def token_symbol(%{"token_symbol" => s}) when is_binary(s) and s != "", do: s
  def token_symbol(_), do: "TOKEN"

  @doc "First letter of the token symbol for the round token icon fallback."
  def token_letter(order) do
    case token_symbol(order) do
      "" -> "?"
      s -> s |> String.first() |> to_string() |> String.upcase()
    end
  end

  # ── Numeric formatters ────────────────────────────────────────────────────

  def format_token_qty(nil), do: "—"

  def format_token_qty(val) when is_number(val) do
    cond do
      abs(val) >= 1000 -> format_float(val, 0)
      abs(val) >= 1 -> format_float(val, 2)
      true -> format_float(val, 4)
    end
  end

  def format_token_qty(_), do: "—"

  def format_sol(nil), do: "—"

  def format_sol(val) when is_number(val) do
    format_float(val, 4)
  end

  def format_sol(_), do: "—"

  def format_usd(nil), do: ""

  def format_usd(val) when is_number(val) do
    "≈ $" <> format_float(abs(val), 2)
  end

  def format_usd(_), do: ""

  def format_percent(nil), do: "—"

  def format_percent(val) when is_number(val) do
    format_float(abs(val), 2) <> "%"
  end

  def format_percent(_), do: "—"

  defp format_float(val, digits) when is_number(val) do
    fmt = "~." <> Integer.to_string(digits) <> "f"
    :io_lib.format(fmt, [val * 1.0]) |> IO.iodata_to_binary()
  end

  # ── Profit ────────────────────────────────────────────────────────────────

  def profit_color(%{"filled" => false}), do: "text-[#EF4444]"

  def profit_color(%{"profit_ui" => v}) when is_number(v) and v < 0,
    do: "text-[#EF4444]"

  def profit_color(_), do: "text-[#22C55E]"

  def format_profit_with_sign(nil), do: "—"

  def format_profit_with_sign(v) when is_number(v) do
    sign = if v >= 0, do: "+", else: "−"
    sign <> format_float(abs(v), profit_digits(abs(v)))
  end

  def format_profit_with_sign(_), do: "—"

  defp profit_digits(abs_v) when abs_v >= 1000, do: 0
  defp profit_digits(abs_v) when abs_v >= 1, do: 2
  defp profit_digits(_), do: 4

  def format_profit_pct(nil), do: ""

  def format_profit_pct(v) when is_number(v) do
    sign = if v >= 0, do: "+", else: "−"
    "(" <> sign <> format_float(abs(v), 2) <> "%)"
  end

  def format_profit_pct(_), do: ""

  @doc """
  Returns a percent for the `profit_pct` field if present, otherwise
  estimates it from `profit_ui` / `sol_amount_ui` for sells, or from
  the multiplier for buys. Returns `nil` when we don't have enough info.
  """
  def profit_pct(order) do
    cond do
      is_number(order["profit_pct"]) -> order["profit_pct"]
      is_number(order["multiplier"]) -> (order["multiplier"] - 1.0) * 100
      true -> nil
    end
  end

  # ── Fill chance / conviction ──────────────────────────────────────────────

  def fill_chance(%{"fill_chance_pct" => p}) when is_number(p), do: p
  def fill_chance(_), do: nil

  def conviction_label(%{"conviction_label" => l}) when is_binary(l) and l != "", do: l

  def conviction_label(order) do
    case fill_chance(order) do
      p when is_number(p) and p >= 70 -> "Conservative"
      p when is_number(p) and p >= 40 -> "Moderate"
      p when is_number(p) -> "Aggressive"
      _ -> "—"
    end
  end

  @doc """
  Returns a marker position (0–100 inclusive) for the conviction bar.
  Higher fill chance → further left (conservative); lower → further
  right (aggressive). Matches the rainbow gradient green → yellow → red.
  """
  def conviction_marker_pct(order) do
    case fill_chance(order) do
      p when is_number(p) ->
        # Clamp 0..100 then invert so low risk sits at the green end.
        pct = max(0.0, min(100.0, p * 1.0))
        100.0 - pct

      _ ->
        50.0
    end
  end

  # ── Wallet + tx + time ────────────────────────────────────────────────────

  def wallet_label(%{"wallet_truncated" => w}) when is_binary(w) and w != "", do: w

  def wallet_label(%{"wallet_address" => w}) when is_binary(w) and byte_size(w) > 9 do
    "#{binary_part(w, 0, 4)}…#{binary_part(w, byte_size(w) - 4, 4)}"
  end

  def wallet_label(_), do: ""

  def tx_label(%{"tx_signature" => sig}) when is_binary(sig) and byte_size(sig) > 10 do
    "#{binary_part(sig, 0, 6)}…#{binary_part(sig, byte_size(sig) - 6, 6)}"
  end

  def tx_label(_), do: ""

  def relative_time(ts) when is_integer(ts) do
    now = System.system_time(:second)
    delta = max(0, now - ts)

    cond do
      delta < 60 -> "just now"
      delta < 3600 -> "#{div(delta, 60)}m ago"
      delta < 86_400 -> "#{div(delta, 3600)}h ago"
      true -> "#{div(delta, 86_400)}d ago"
    end
  end

  def relative_time(%DateTime{} = dt), do: relative_time(DateTime.to_unix(dt))
  def relative_time(_), do: ""

  # ── Quote + tagline ───────────────────────────────────────────────────────

  def quote_text(%{"quote" => q}) when is_binary(q) and q != "", do: q

  def quote_text(_),
    do: "The Solana DEX where you gamble for a better price than market."

  @doc "Marketing tagline shown in the header gradient."
  def tagline, do: "Gamble for a better price than market"
end
