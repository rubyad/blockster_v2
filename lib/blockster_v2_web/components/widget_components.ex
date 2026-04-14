defmodule BlocksterV2Web.WidgetComponents do
  @moduledoc """
  Dispatcher from an ad_banner row to either the existing image-based ad
  renderer (when `widget_type` is nil) or a real-time widget component
  (when `widget_type` matches one of the 14 shipped widgets).

  Phase 3 added `rt_skyscraper` + `fs_skyscraper`. Phase 4 adds the four
  RogueTrader chart widgets (`rt_chart_landscape`, `rt_chart_portrait`,
  `rt_full_card`, `rt_square_compact`). Remaining widget_types raise an
  explicit ArgumentError so mis-typed admin configs surface loudly and
  the nil-fallback keeps the existing image ads untouched.

  Plan: docs/solana/realtime_widgets_plan.md · §F "Widget components".
  """

  use Phoenix.Component

  alias BlocksterV2.Ads.Banner

  import BlocksterV2Web.Widgets.FsSkyscraper, only: [fs_skyscraper: 1]
  import BlocksterV2Web.Widgets.RtSkyscraper, only: [rt_skyscraper: 1]
  import BlocksterV2Web.Widgets.RtChartLandscape, only: [rt_chart_landscape: 1]
  import BlocksterV2Web.Widgets.RtChartPortrait, only: [rt_chart_portrait: 1]
  import BlocksterV2Web.Widgets.RtFullCard, only: [rt_full_card: 1]
  import BlocksterV2Web.Widgets.RtSquareCompact, only: [rt_square_compact: 1]
  import BlocksterV2Web.Widgets.RtTicker, only: [rt_ticker: 1]
  import BlocksterV2Web.Widgets.FsTicker, only: [fs_ticker: 1]
  import BlocksterV2Web.Widgets.RtLeaderboardInline, only: [rt_leaderboard_inline: 1]
  import BlocksterV2Web.Widgets.FsHeroPortrait, only: [fs_hero_portrait: 1]
  import BlocksterV2Web.Widgets.FsHeroLandscape, only: [fs_hero_landscape: 1]

  @known_widget_types Banner.valid_widget_types()

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :trades, :list, default: []
  attr :selections, :map, default: %{}
  attr :chart_data, :map, default: %{}
  attr :class, :string, default: nil
  attr :rest, :global

  def widget_or_ad(%{banner: %{widget_type: nil}} = assigns) do
    ~H"""
    <BlocksterV2Web.DesignSystem.ad_banner banner={@banner} class={@class} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_skyscraper"}} = assigns) do
    ~H"""
    <.fs_skyscraper banner={@banner} trades={@trades} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_skyscraper"}} = assigns) do
    ~H"""
    <.rt_skyscraper banner={@banner} bots={@bots} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_chart_landscape"}} = assigns) do
    ~H"""
    <.rt_chart_landscape
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_chart_portrait"}} = assigns) do
    ~H"""
    <.rt_chart_portrait
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_full_card"}} = assigns) do
    ~H"""
    <.rt_full_card
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_square_compact"}} = assigns) do
    ~H"""
    <.rt_square_compact
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_ticker"}} = assigns) do
    ~H"""
    <.rt_ticker banner={@banner} bots={@bots} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_ticker"}} = assigns) do
    ~H"""
    <.fs_ticker banner={@banner} trades={@trades} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_leaderboard_inline"}} = assigns) do
    ~H"""
    <.rt_leaderboard_inline banner={@banner} bots={@bots} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_hero_portrait"}} = assigns) do
    ~H"""
    <.fs_hero_portrait
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_hero_landscape"}} = assigns) do
    ~H"""
    <.fs_hero_landscape
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: type}} = assigns)
      when type in @known_widget_types do
    raise ArgumentError,
          "widget component not yet implemented (Phase 3+): #{type}. " <>
            "Banner id=#{inspect(assigns.banner.id)} placement=#{inspect(assigns.banner.placement)}."
  end

  def widget_or_ad(%{banner: %{widget_type: type}}) do
    raise ArgumentError,
          "unknown widget_type: #{inspect(type)}. " <>
            "Expected nil or one of: #{Enum.join(@known_widget_types, ", ")}."
  end
end
