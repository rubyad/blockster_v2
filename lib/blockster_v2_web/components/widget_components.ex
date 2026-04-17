defmodule BlocksterV2Web.WidgetComponents do
  @moduledoc """
  Dispatcher from an ad_banner row to either the existing image-based ad
  renderer (when `widget_type` is nil) or a real-time widget component
  (when `widget_type` matches one of the 14 shipped widgets).

  Phase 3 added `rt_skyscraper` + `fs_skyscraper`. Phase 4 added the four
  RogueTrader chart widgets (`rt_chart_landscape`, `rt_chart_portrait`,
  `rt_full_card`, `rt_square_compact`). Phase 5 added tickers, the
  RogueTrader leaderboard, and the FateSwap hero cards. Phase 6 adds the
  three remaining sidebar tiles (`rt_sidebar_tile`, `fs_square_compact`,
  `fs_sidebar_tile`). Unknown widget_types raise an explicit ArgumentError
  so mis-typed admin configs surface loudly; the nil-fallback keeps the
  existing image ads untouched.

  Plan: docs/solana/realtime_widgets_plan.md · §F "Widget components".
  """

  use Phoenix.Component

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2.Widgets.TrackerStatus

  import BlocksterV2Web.Widgets.FsSkyscraper, only: [fs_skyscraper: 1]
  import BlocksterV2Web.Widgets.RtSkyscraper, only: [rt_skyscraper: 1]
  import BlocksterV2Web.Widgets.RtChartLandscape, only: [rt_chart_landscape: 1]
  import BlocksterV2Web.Widgets.RtChartPortrait, only: [rt_chart_portrait: 1]
  import BlocksterV2Web.Widgets.RtFullCard, only: [rt_full_card: 1]
  import BlocksterV2Web.Widgets.RtSquareCompact, only: [rt_square_compact: 1]
  import BlocksterV2Web.Widgets.RtSidebarTile, only: [rt_sidebar_tile: 1]
  import BlocksterV2Web.Widgets.RtTicker, only: [rt_ticker: 1]
  import BlocksterV2Web.Widgets.FsTicker, only: [fs_ticker: 1]
  import BlocksterV2Web.Widgets.RtLeaderboardInline, only: [rt_leaderboard_inline: 1]
  import BlocksterV2Web.Widgets.FsHeroPortrait, only: [fs_hero_portrait: 1]
  import BlocksterV2Web.Widgets.FsHeroLandscape, only: [fs_hero_landscape: 1]
  import BlocksterV2Web.Widgets.FsSquareCompact, only: [fs_square_compact: 1]
  import BlocksterV2Web.Widgets.FsSidebarTile, only: [fs_sidebar_tile: 1]
  import BlocksterV2Web.Widgets.CfSidebarDemo, only: [cf_sidebar_demo: 1]
  import BlocksterV2Web.Widgets.CfInlineLandscapeDemo, only: [cf_inline_landscape_demo: 1]
  import BlocksterV2Web.Widgets.CfPortraitDemo, only: [cf_portrait_demo: 1]
  import BlocksterV2Web.Widgets.CfSidebarTile, only: [cf_sidebar_tile: 1]
  import BlocksterV2Web.Widgets.CfInlineLandscape, only: [cf_inline_landscape: 1]
  import BlocksterV2Web.Widgets.CfPortrait, only: [cf_portrait: 1]

  @known_widget_types Banner.valid_widget_types()

  # Renders an article-inline ad slot responsively. Landscape widgets and
  # `luxury_watch_split` don't read well at mobile width, so they auto-swap
  # to their portrait/editorial siblings below the `lg` breakpoint. The DB
  # row is untouched — only the struct passed to `widget_or_ad` is cloned
  # with a swapped widget_type/template.
  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :trades, :list, default: []
  attr :selections, :map, default: %{}
  attr :chart_data, :map, default: %{}
  attr :tracker_errors, :map, default: %{}
  attr :cf_games, :list, default: []
  attr :class, :string, default: nil

  def inline_ad_slot(assigns) do
    assigns = assign(assigns, :mobile_banner, mobile_swap(assigns.banner))

    ~H"""
    <div class={if @mobile_banner, do: "hidden lg:block", else: ""}>
      <.widget_or_ad
        banner={@banner}
        bots={@bots}
        trades={@trades}
        selections={@selections}
        chart_data={@chart_data}
        tracker_errors={@tracker_errors}
        cf_games={@cf_games}
      />
    </div>
    <%= if @mobile_banner do %>
      <div class="lg:hidden">
        <.widget_or_ad
          banner={@mobile_banner}
          bots={@bots}
          trades={@trades}
          selections={@selections}
          chart_data={@chart_data}
          tracker_errors={@tracker_errors}
          cf_games={@cf_games}
        />
      </div>
    <% end %>
    """
  end

  # Desktop → mobile banner transform. Returns nil when the same render
  # works on both viewports.
  defp mobile_swap(%{widget_type: "cf_inline_landscape_demo"} = b),
    do: %{b | widget_type: "cf_portrait_demo"}

  defp mobile_swap(%{widget_type: "rt_chart_landscape"} = b),
    do: %{b | widget_type: "rt_chart_portrait"}

  defp mobile_swap(%{template: "luxury_watch_split"} = b),
    do: %{b | template: "luxury_watch"}

  defp mobile_swap(_), do: nil

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :trades, :list, default: []
  attr :selections, :map, default: %{}
  attr :chart_data, :map, default: %{}
  attr :tracker_errors, :map, default: %{}
  attr :cf_games, :list, default: []
  attr :class, :string, default: nil
  attr :rest, :global

  def widget_or_ad(%{banner: %{widget_type: nil}} = assigns) do
    ~H"""
    <BlocksterV2Web.DesignSystem.ad_banner banner={@banner} class={@class} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_skyscraper"}} = assigns) do
    ~H"""
    <.fs_skyscraper
      banner={@banner}
      trades={@trades}
      tracker_error?={TrackerStatus.widget_error?("fs_skyscraper", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_skyscraper"}} = assigns) do
    ~H"""
    <.rt_skyscraper
      banner={@banner}
      bots={@bots}
      tracker_error?={TrackerStatus.widget_error?("rt_skyscraper", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_chart_landscape"}} = assigns) do
    ~H"""
    <.rt_chart_landscape
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
      tracker_error?={TrackerStatus.widget_error?("rt_chart_landscape", @tracker_errors)}
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
      tracker_error?={TrackerStatus.widget_error?("rt_chart_portrait", @tracker_errors)}
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
      tracker_error?={TrackerStatus.widget_error?("rt_full_card", @tracker_errors)}
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
      tracker_error?={TrackerStatus.widget_error?("rt_square_compact", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_sidebar_tile"}} = assigns) do
    ~H"""
    <.rt_sidebar_tile
      banner={@banner}
      bots={@bots}
      selection={Map.get(@selections, @banner.id)}
      chart_data={@chart_data}
      tracker_error?={TrackerStatus.widget_error?("rt_sidebar_tile", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_square_compact"}} = assigns) do
    ~H"""
    <.fs_square_compact
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
      tracker_error?={TrackerStatus.widget_error?("fs_square_compact", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_sidebar_tile"}} = assigns) do
    ~H"""
    <.fs_sidebar_tile
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
      tracker_error?={TrackerStatus.widget_error?("fs_sidebar_tile", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_ticker"}} = assigns) do
    ~H"""
    <.rt_ticker
      banner={@banner}
      bots={@bots}
      tracker_error?={TrackerStatus.widget_error?("rt_ticker", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_ticker"}} = assigns) do
    ~H"""
    <.fs_ticker
      banner={@banner}
      trades={@trades}
      tracker_error?={TrackerStatus.widget_error?("fs_ticker", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_leaderboard_inline"}} = assigns) do
    ~H"""
    <.rt_leaderboard_inline
      banner={@banner}
      bots={@bots}
      tracker_error?={TrackerStatus.widget_error?("rt_leaderboard_inline", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_hero_portrait"}} = assigns) do
    ~H"""
    <.fs_hero_portrait
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
      tracker_error?={TrackerStatus.widget_error?("fs_hero_portrait", @tracker_errors)}
    />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "fs_hero_landscape"}} = assigns) do
    ~H"""
    <.fs_hero_landscape
      banner={@banner}
      trades={@trades}
      selection={Map.get(@selections, @banner.id)}
      tracker_error?={TrackerStatus.widget_error?("fs_hero_landscape", @tracker_errors)}
    />
    """
  end

  # Coin Flip live widgets (use cf_games data)
  def widget_or_ad(%{banner: %{widget_type: "cf_sidebar_tile"}} = assigns) do
    ~H"""
    <.cf_sidebar_tile banner={@banner} cf_games={@cf_games} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "cf_inline_landscape"}} = assigns) do
    ~H"""
    <.cf_inline_landscape banner={@banner} cf_games={@cf_games} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "cf_portrait"}} = assigns) do
    ~H"""
    <.cf_portrait banner={@banner} cf_games={@cf_games} />
    """
  end

  # Coin Flip demo widgets (no live data needed)
  def widget_or_ad(%{banner: %{widget_type: "cf_sidebar_demo"}} = assigns) do
    ~H"""
    <.cf_sidebar_demo banner={@banner} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "cf_inline_landscape_demo"}} = assigns) do
    ~H"""
    <.cf_inline_landscape_demo banner={@banner} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: "cf_portrait_demo"}} = assigns) do
    ~H"""
    <.cf_portrait_demo banner={@banner} />
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
