defmodule BlocksterV2.Widgets.TrackerStatus do
  @moduledoc """
  Thin facade over the three widget pollers' `get_last_error/0`
  accessors. Exposes a map `%{fs_feed: err, rt_bots: err, rt_chart: err}`
  so the `WidgetEvents` macro can assign widget-level error flags
  without knowing the internals of each tracker.

  Each underlying getter is wrapped in `try/catch :exit` so a missing
  or overloaded tracker process returns `nil` (no error) rather than
  crashing the LiveView mount.
  """

  alias BlocksterV2.Widgets.{
    FateSwapFeedTracker,
    RogueTraderBotsTracker,
    RogueTraderChartTracker
  }

  @doc "Returns `%{fs_feed: err | nil, rt_bots: err | nil, rt_chart: err | nil}`."
  def errors do
    %{
      fs_feed: safe(FateSwapFeedTracker),
      rt_bots: safe(RogueTraderBotsTracker),
      rt_chart: safe(RogueTraderChartTracker)
    }
  end

  @doc "Returns true when at least one tracker is reporting an error."
  def any_errors?(%{} = errors) do
    Enum.any?(errors, fn {_k, v} -> not is_nil(v) end)
  end

  def any_errors?(_), do: false

  @doc """
  Given a widget_type and the errors map, returns `true` if the
  tracker feeding that widget is in an error state. Used by the
  dispatcher to decide whether to render the shimmer skeleton or the
  error placeholder.
  """
  def widget_error?(widget_type, errors) when is_binary(widget_type) and is_map(errors) do
    case family(widget_type) do
      :fs -> not is_nil(errors[:fs_feed])
      :rt_snapshot -> not is_nil(errors[:rt_bots])
      :rt_chart -> not is_nil(errors[:rt_bots]) or not is_nil(errors[:rt_chart])
      _ -> false
    end
  end

  def widget_error?(_, _), do: false

  defp family("fs_" <> _), do: :fs
  defp family("rt_chart_" <> _), do: :rt_chart
  defp family("rt_full_card"), do: :rt_chart
  defp family("rt_square_compact"), do: :rt_chart
  defp family("rt_sidebar_tile"), do: :rt_chart
  defp family("rt_" <> _), do: :rt_snapshot
  defp family(_), do: :unknown

  defp safe(module) do
    try do
      module.get_last_error()
    rescue
      _ -> nil
    end
  end
end
