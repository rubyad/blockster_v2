defmodule BlocksterV2.Widgets.ClickRouter do
  @moduledoc """
  Builds the redirect URL for a widget click based on the subject captured at
  render time.

  Self-selected RogueTrader widgets carry `{bot_id, timeframe}` as the subject
  and land on the bot detail page. Self-selected FateSwap widgets carry an
  order id (binary) and land on the order's share page. All-data widgets
  (skyscrapers, tickers, leaderboards) fall back to the sister-project
  homepage via the `:rt` / `:fs` atom subjects.

  Per Decision #7 — the subject value is the snapshot taken when the widget
  was last rendered, so the click destination always matches what the user
  actually saw (not a potentially-rotated new selection).
  """

  @rt_base "https://roguetrader.io"
  @fs_base "https://fateswap.io"

  @doc """
  Returns the absolute URL for a widget click.

  ## Clauses
    * `{bot_id, _tf}` where `bot_id` is a binary → `#{@rt_base}/bot/:bot_id`
    * `order_id` when is_binary(order_id)       → `#{@fs_base}/orders/:order_id`
    * `:rt` / `"rt"`                            → `#{@rt_base}`
    * `:fs` / `"fs"`                            → `#{@fs_base}`
    * anything else                             → `"/"` (safe fallback)
  """
  def url_for(_banner_id, subject), do: destination(subject)

  @doc """
  Same as `url_for/2` but without the banner id for the callers that only
  have the subject (e.g. component render-time href).
  """
  def url_for(subject), do: destination(subject)

  defp destination({bot_id, _tf}) when is_binary(bot_id) and byte_size(bot_id) > 0,
    do: "#{@rt_base}/bot/#{resolve_numeric_id(bot_id)}"

  defp destination(order_id) when is_binary(order_id) and byte_size(order_id) > 0 do
    case order_id do
      "rt" -> @rt_base
      "fs" -> @fs_base
      _ -> "#{@fs_base}/orders/#{order_id}"
    end
  end

  defp destination(:rt), do: @rt_base
  defp destination(:fs), do: @fs_base
  defp destination(_), do: "/"

  # RogueTrader bot pages are keyed on the numeric `bot_id`, not the slug/name.
  # The widget subject still carries the slug (for UI lookup), so translate it
  # to the numeric id via the bots cache. Falls back to the original identifier
  # if the bot isn't in the cache (URL may be stale but never crashes).
  defp resolve_numeric_id(id) do
    case BlocksterV2.Widgets.RogueTraderBotsTracker.get_bot(id) do
      %{"bot_id" => n} when is_integer(n) -> Integer.to_string(n)
      %{"bot_id" => n} when is_binary(n) and n != "" -> n
      _ -> id
    end
  rescue
    _ -> id
  end

  @doc "RogueTrader base URL."
  def rt_base, do: @rt_base

  @doc "FateSwap base URL."
  def fs_base, do: @fs_base
end
