defmodule BlocksterV2Web.Widgets.RtChartHelpers do
  @moduledoc """
  Shared formatting + bot-lookup helpers for the RogueTrader chart
  widgets (`rt_chart_landscape`, `rt_chart_portrait`, `rt_full_card`,
  `rt_square_compact`).

  Each chart widget receives the same upstream data:

    * `banner` — the `ad_banner` row
    * `bots` — the current list from `RogueTraderBotsTracker.get_bots/0`
    * `selection` — `{bot_id, tf}` picked by `WidgetSelector`, or `nil`
    * `chart_data` — map of `{bot_id, tf}` → `[%{time, value}]`

  The helpers resolve the bot + points + header numbers from those
  inputs so each component template can stay presentational.
  """

  @timeframes ~w(1h 6h 24h 48h 7d)

  def timeframes, do: @timeframes

  def tf_label("1h"), do: "1H"
  def tf_label("6h"), do: "6H"
  def tf_label("24h"), do: "24H"
  def tf_label("48h"), do: "48H"
  def tf_label("7d"), do: "7D"
  def tf_label(tf) when is_binary(tf), do: String.upcase(tf)
  def tf_label(_), do: ""

  @doc "Looks up the bot map for the current selection, falling back to the first bot when empty."
  def resolve_bot(bots, {bot_id, _tf}) when is_list(bots) and is_binary(bot_id) do
    Enum.find(bots, fn b ->
      b["slug"] == bot_id or b["bot_id"] == bot_id
    end) || Enum.at(bots, 0)
  end

  def resolve_bot(bots, _) when is_list(bots), do: Enum.at(bots, 0)
  def resolve_bot(_, _), do: nil

  def resolve_tf({_bot_id, tf}) when tf in @timeframes, do: tf
  def resolve_tf(_), do: "7d"

  def resolve_points(chart_data, {bot_id, tf})
      when is_map(chart_data) and is_binary(bot_id) and is_binary(tf) do
    Map.get(chart_data, {bot_id, tf}, [])
  end

  def resolve_points(_, _), do: []

  @doc "Serialises points as `[%{time, value}]` JSON. Handles both atom-keyed and string-keyed maps."
  def points_as_json(points) when is_list(points) do
    points
    |> Enum.map(&point_to_json/1)
    |> Enum.reject(&is_nil/1)
    |> Jason.encode!()
  end

  def points_as_json(_), do: "[]"

  defp point_to_json(%{"time" => t, "value" => v}) when not is_nil(t) and not is_nil(v) do
    %{time: t, value: v}
  end

  defp point_to_json(%{time: t, value: v}) when not is_nil(t) and not is_nil(v) do
    %{time: t, value: v}
  end

  defp point_to_json(_), do: nil

  # ── Header helpers ────────────────────────────────────────────────────────

  def bot_name(nil), do: "—"

  def bot_name(bot) when is_map(bot) do
    (bot["name"] || bot["slug"] || bot["bot_id"] || "")
    |> to_string()
    |> String.upcase()
  end

  def bot_slug(nil), do: ""

  def bot_slug(bot) when is_map(bot) do
    bot["slug"] || bot["bot_id"] || ""
  end

  def group_key(nil), do: ""

  def group_key(bot) when is_map(bot) do
    (bot["group_name"] || bot["group_id"] || "")
    |> to_string()
    |> String.downcase()
  end

  def group_label(bot) do
    bot |> group_key() |> String.upcase()
  end

  def group_hex(bot) do
    case group_key(bot) do
      "crypto" -> "#3B82F6"
      "equities" -> "#10B981"
      "indexes" -> "#8B5CF6"
      "commodities" -> "#F59E0B"
      "forex" -> "#F43F5E"
      _ -> "#6B7280"
    end
  end

  # ── Price / change formatters ─────────────────────────────────────────────

  def format_price(nil), do: "—"

  def format_price(val) when is_number(val) do
    :io_lib.format("~.4f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  def format_price(_), do: "—"

  def change_for(bot, tf) do
    case tf do
      "1h" -> bot && bot["lp_price_change_1h_pct"]
      "6h" -> bot && bot["lp_price_change_6h_pct"]
      "24h" -> bot && bot["lp_price_change_24h_pct"]
      "48h" -> bot && bot["lp_price_change_48h_pct"]
      "7d" -> bot && bot["lp_price_change_7d_pct"]
      _ -> nil
    end
  end

  def format_change(nil), do: "—"

  def format_change(v) when is_number(v) do
    sign = if v >= 0, do: "+", else: "−"
    mag = :io_lib.format("~.2f", [abs(v) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}#{mag}%"
  end

  def format_change(_), do: "—"

  def change_color(v) when is_number(v) and v >= 0, do: "#22C55E"
  def change_color(v) when is_number(v), do: "#EF4444"
  def change_color(_), do: "#6B7280"

  def change_bg(v) when is_number(v) and v >= 0, do: "rgba(34, 197, 94, 0.10)"
  def change_bg(v) when is_number(v), do: "rgba(239, 68, 68, 0.10)"
  def change_bg(_), do: "rgba(255, 255, 255, 0.05)"

  @doc "Returns `%{high, low}` for the supplied points, or `nil` if empty."
  def high_low([]), do: nil
  def high_low(points) when is_list(points) do
    values =
      points
      |> Enum.map(fn
        %{"value" => v} when is_number(v) -> v
        %{value: v} when is_number(v) -> v
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case values do
      [] -> nil
      _ -> %{high: Enum.max(values), low: Enum.min(values)}
    end
  end

  def high_low(_), do: nil

  # ── Stat card helpers (rt_full_card) ──────────────────────────────────────

  def format_with_commas(nil), do: "—"

  def format_with_commas(val) when is_number(val) do
    val
    |> trunc()
    |> Integer.to_string()
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.intersperse(',')
    |> to_string()
  end

  def format_with_commas(_), do: "—"

  def format_sol(nil), do: "—"

  def format_sol(val) when is_number(val) do
    :io_lib.format("~.2f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  def format_sol(_), do: "—"

  def format_percent(nil), do: "—"

  def format_percent(val) when is_number(val) do
    rounded = :io_lib.format("~.1f", [val * 1.0]) |> IO.iodata_to_binary()
    "#{rounded}%"
  end

  def format_percent(_), do: "—"

  def format_rank(nil), do: "—"
  def format_rank(n) when is_integer(n) and n > 0, do: "#{n}"
  def format_rank(n) when is_number(n), do: "#{trunc(n)}"
  def format_rank(_), do: "—"

  def wins_settled(bot) when is_map(bot) do
    case bot["wins_settled_7d"] do
      %{"wins" => w, "total" => t} when is_number(w) and is_number(t) -> "#{trunc(w)}/#{trunc(t)}"
      %{wins: w, total: t} when is_number(w) and is_number(t) -> "#{trunc(w)}/#{trunc(t)}"
      _ -> "—"
    end
  end

  def wins_settled(_), do: "—"
end
