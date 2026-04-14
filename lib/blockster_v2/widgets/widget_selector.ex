defmodule BlocksterV2.Widgets.WidgetSelector do
  @moduledoc """
  Pure functions that pick the subject (bot+timeframe or order_id) a single
  self-selecting widget should render right now.

  Called by each tracker at the end of a successful poll for every active
  banner whose `widget_type` self-selects. The tracker caches the pick in
  the `widget_selections` Mnesia table and broadcasts on
  `"widgets:selection:\#{banner_id}"` only when the pick has changed.

  All pickers are side-effect-free — callers supply data (list of bot maps,
  list of trade maps) and the banner's `widget_config` map and get back a
  subject tuple (`{bot_id, tf}`), a string (`order_id`), or `nil` when no
  candidate is available. See [Self-Selection Logic](../docs/solana/realtime_widgets_plan.md)
  for the decision matrix.

  Data shapes match the JSON returned by the sister-app APIs — string keys,
  numeric values, no Elixir structs.
  """

  alias BlocksterV2.Ads
  alias BlocksterV2.Ads.Banner

  @rt_selection_modes ~w(biggest_gainer biggest_mover highest_aum top_ranked fixed)a
  @fs_selection_modes ~w(biggest_profit biggest_discount most_recent_filled random_recent fixed)a
  @rt_timeframes ~w(1h 6h 24h 48h 7d)

  # ── Public helpers ────────────────────────────────────────────────────────

  def rt_selection_modes, do: @rt_selection_modes
  def fs_selection_modes, do: @fs_selection_modes
  def rt_timeframes, do: @rt_timeframes

  @doc """
  Picks the current subject for one RogueTrader banner.

  Returns `{bot_id, timeframe}` or `nil` if no candidate exists.
  """
  def pick_rt(bots, %Banner{widget_config: config}) when is_list(bots) do
    pick_rt(bots, config)
  end

  def pick_rt(bots, config) when is_list(bots) and is_map(config) do
    mode = resolve_mode(config, :biggest_gainer, @rt_selection_modes)
    do_pick_rt(mode, bots, config)
  end

  def pick_rt(_bots, _), do: nil

  @doc """
  Picks the current subject for one FateSwap banner.

  Returns an `order_id` string or `nil`.
  """
  def pick_fs(trades, %Banner{widget_config: config}) when is_list(trades) do
    pick_fs(trades, config)
  end

  def pick_fs(trades, config) when is_list(trades) and is_map(config) do
    mode = resolve_mode(config, :biggest_profit, @fs_selection_modes)
    do_pick_fs(mode, trades, config)
  end

  def pick_fs(_trades, _), do: nil

  @doc """
  Runs `pick_rt/2` / `pick_fs/2` for every active widget banner in the given
  family (`:rt` or `:fs`) using the supplied fresh data and returns a list of
  `{banner, subject}` tuples. `subject` is `nil` when no candidate was found.

  This is what a tracker calls at the end of a successful poll.
  """
  def pick_for_family(:rt, bots, banners) when is_list(bots) and is_list(banners) do
    for banner <- banners, rt?(banner.widget_type), do: {banner, pick_rt(bots, banner)}
  end

  def pick_for_family(:fs, trades, banners) when is_list(trades) and is_list(banners) do
    for banner <- banners, fs?(banner.widget_type), do: {banner, pick_fs(trades, banner)}
  end

  def pick_for_family(_, _, _), do: []

  @doc "Splits a list of banners by family (returns `%{rt: [...], fs: [...]}`)."
  def partition_banners(banners) when is_list(banners) do
    Enum.reduce(banners, %{rt: [], fs: []}, fn banner, acc ->
      cond do
        rt?(banner.widget_type) -> %{acc | rt: [banner | acc.rt]}
        fs?(banner.widget_type) -> %{acc | fs: [banner | acc.fs]}
        true -> acc
      end
    end)
  end

  @doc """
  Fetches the active widget banners for the given family from the DB.
  Callers should prefer this over hitting `Ads.list_widget_banners/0`
  directly so the family filter stays in one place.
  """
  def list_banners(:rt), do: Ads.list_widget_banners() |> Enum.filter(&rt?(&1.widget_type))
  def list_banners(:fs), do: Ads.list_widget_banners() |> Enum.filter(&fs?(&1.widget_type))
  def list_banners(:all), do: Ads.list_widget_banners()

  # ── RogueTrader modes ─────────────────────────────────────────────────────

  defp do_pick_rt(:biggest_gainer, bots, _config), do: rank_and_pick(bots, & &1)
  defp do_pick_rt(:biggest_mover, bots, _config), do: rank_and_pick(bots, &abs/1)

  defp do_pick_rt(:highest_aum, bots, _config) do
    bots
    |> Enum.filter(&number?(&1["sol_balance"]))
    |> Enum.max_by(& &1["sol_balance"], fn -> nil end)
    |> case do
      nil -> nil
      bot -> {bot_id(bot), timeframe_from(bot) || "7d"}
    end
  end

  defp do_pick_rt(:top_ranked, bots, _config) do
    bots
    |> Enum.filter(&number?(&1["lp_price"]))
    |> Enum.sort_by(
      fn bot -> rank_or_price(bot) end,
      :asc
    )
    |> List.first()
    |> case do
      nil -> nil
      bot -> {bot_id(bot), timeframe_from(bot) || "24h"}
    end
  end

  defp do_pick_rt(:fixed, _bots, config) do
    case {config["bot_id"], config["timeframe"]} do
      {id, _} when not is_binary(id) or id == "" -> nil
      {id, tf} -> {id, normalize_tf(tf) || "7d"}
    end
  end

  defp do_pick_rt(_unknown, _bots, _config), do: nil

  # Build the {bot_id, tf, change_pct} candidate list and pick the max by
  # the given ranker (identity = gainer, abs = mover).
  defp rank_and_pick(bots, ranker) when is_function(ranker, 1) do
    candidates =
      for bot <- bots,
          tf <- @rt_timeframes,
          change = change_pct_for(bot, tf),
          is_number(change) do
        {bot_id(bot), tf, change}
      end

    case candidates do
      [] ->
        nil

      list ->
        {bot_id, tf, _} = Enum.max_by(list, fn {_, _, c} -> ranker.(c) end)
        if is_binary(bot_id) and bot_id != "", do: {bot_id, tf}, else: nil
    end
  end

  defp change_pct_for(bot, tf) do
    case tf do
      "1h" -> bot["lp_price_change_1h_pct"]
      "6h" -> bot["lp_price_change_6h_pct"]
      "24h" -> bot["lp_price_change_24h_pct"]
      "48h" -> bot["lp_price_change_48h_pct"]
      "7d" -> bot["lp_price_change_7d_pct"]
      _ -> nil
    end
  end

  defp bot_id(bot) when is_map(bot) do
    case bot["slug"] || bot["bot_id"] || bot[:slug] || bot[:bot_id] do
      id when is_binary(id) -> id
      id when is_integer(id) -> Integer.to_string(id)
      _ -> nil
    end
  end

  defp timeframe_from(bot) do
    tf = bot["default_timeframe"] || bot[:default_timeframe]
    if tf in @rt_timeframes, do: tf
  end

  defp rank_or_price(bot) do
    case bot["rank"] do
      r when is_integer(r) and r > 0 -> r
      _ -> -(bot["lp_price"] || 0.0) * 1.0
    end
  end

  # ── FateSwap modes ────────────────────────────────────────────────────────

  defp do_pick_fs(:biggest_profit, trades, _config) do
    trades
    |> Enum.filter(&settled_and_filled?/1)
    |> Enum.max_by(&profit_lamports/1, fn -> nil end)
    |> order_id_or_nil()
  end

  defp do_pick_fs(:biggest_discount, trades, _config) do
    trades
    |> Enum.filter(fn t ->
      settled?(t) and number?(t["discount_pct"]) and t["discount_pct"] > 0
    end)
    |> Enum.max_by(& &1["discount_pct"], fn -> nil end)
    |> order_id_or_nil()
  end

  defp do_pick_fs(:most_recent_filled, trades, _config) do
    trades
    |> Enum.filter(&settled_and_filled?/1)
    |> Enum.sort_by(&settled_at/1, :desc)
    |> List.first()
    |> order_id_or_nil()
  end

  defp do_pick_fs(:random_recent, trades, _config) do
    trades
    |> Enum.filter(&settled?/1)
    |> Enum.take(20)
    |> case do
      [] -> nil
      list -> list |> Enum.random() |> order_id_or_nil()
    end
  end

  defp do_pick_fs(:fixed, _trades, config) do
    case config["order_id"] do
      id when is_binary(id) and byte_size(id) > 0 -> id
      _ -> nil
    end
  end

  defp do_pick_fs(_unknown, _trades, _config), do: nil

  defp settled_and_filled?(trade) when is_map(trade) do
    settled?(trade) and
      (trade["filled"] == true or trade["status_text"] in ["ORDER FILLED", "DISCOUNT FILLED"])
  end

  defp settled_and_filled?(_), do: false

  defp settled?(%{"settled_at" => %DateTime{}}), do: true
  defp settled?(%{"settled_at" => ts}) when is_integer(ts) and ts > 0, do: true
  defp settled?(%{"settled_at" => ts}) when is_binary(ts) and byte_size(ts) > 0, do: true
  defp settled?(_), do: false

  defp profit_lamports(%{"profit_lamports" => v}) when is_number(v), do: v
  defp profit_lamports(_), do: 0

  defp settled_at(%{"settled_at" => %DateTime{} = dt}), do: DateTime.to_unix(dt)
  defp settled_at(%{"settled_at" => ts}) when is_integer(ts), do: ts

  defp settled_at(%{"settled_at" => ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  defp settled_at(_), do: 0

  defp order_id_or_nil(nil), do: nil

  defp order_id_or_nil(%{"id" => id}) when is_binary(id) and byte_size(id) > 0, do: id
  defp order_id_or_nil(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp order_id_or_nil(_), do: nil

  # ── Shared helpers ────────────────────────────────────────────────────────

  defp rt?(type), do: is_binary(type) and String.starts_with?(type, "rt_")
  defp fs?(type), do: is_binary(type) and String.starts_with?(type, "fs_")

  defp resolve_mode(config, default, valid_modes) do
    raw = config["selection"] || config[:selection]

    case raw do
      nil ->
        default

      atom when is_atom(atom) ->
        if atom in valid_modes, do: atom, else: :unknown

      str when is_binary(str) ->
        case Enum.find(valid_modes, fn m -> Atom.to_string(m) == str end) do
          nil -> :unknown
          m -> m
        end

      _ ->
        :unknown
    end
  end

  defp normalize_tf(tf) when tf in ~w(1h 6h 24h 48h 7d), do: tf
  defp normalize_tf(_), do: nil

  defp number?(v), do: is_number(v)
end
