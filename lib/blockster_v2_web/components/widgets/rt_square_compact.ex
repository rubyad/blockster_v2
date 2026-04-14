defmodule BlocksterV2Web.Widgets.RtSquareCompact do
  @moduledoc """
  RogueTrader compact tile (200 × 200) — one self-selected bot with
  bid/ask, change %, group tag, and a sparkline.

  Fits the same sidebar slots as `rt_skyscraper`, `rt_sidebar_tile`,
  `play_sidebar_*`, etc. The sparkline is a lightweight-charts Area
  series stripped down (no grid, no axes) — rendered via the dedicated
  `RtSquareCompactWidget` hook.

  Plan: docs/solana/realtime_widgets_plan.md · §F `rt_square_compact`
  Mock: docs/solana/widgets_mocks/rt_square_compact_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.RtChartHelpers

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :selection, :any, default: nil
  attr :chart_data, :map, default: %{}

  def rt_square_compact(assigns) do
    tf = RtChartHelpers.resolve_tf(assigns.selection)
    bot = RtChartHelpers.resolve_bot(assigns.bots, assigns.selection)
    points = RtChartHelpers.resolve_points(assigns.chart_data, assigns.selection)
    change = RtChartHelpers.change_for(bot, tf)

    assigns =
      assigns
      |> assign(:bot, bot)
      |> assign(:tf, tf)
      |> assign(:points_json, RtChartHelpers.points_as_json(points))
      |> assign(:change, change)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell relative w-[200px] h-[200px] flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="RtSquareCompactWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_square_compact"
      data-bot-id={RtChartHelpers.bot_slug(@bot)}
      data-tf={@tf}
      data-change-pct={if is_number(@change), do: Float.to_string(@change * 1.0), else: ""}
    >
      <%!-- Mini chrome strip --%>
      <div class="relative z-10 h-[34px] px-2.5 flex items-center gap-2 border-b border-white/[0.06] shrink-0">
        <span class="relative inline-flex shrink-0" style="line-height:1;">
          <img
            class="h-[20px] w-auto block"
            src="https://ik.imagekit.io/blockster/rogue-logo-white.png"
            alt="Rogue Trader"
          />
          <span
            class="bw-mono"
            style="position:absolute;bottom:-4px;right:0;font-weight:700;font-size:8px;color:#22C55E;letter-spacing:0.28em;line-height:1;"
          >
            TRADER
          </span>
        </span>
        <span class="w-px h-[8px] bg-white/[0.10]"></span>
        <span class="flex-1"></span>
        <span class="bw-display inline-flex items-center gap-1 text-[9px] font-semibold tracking-[0.12em] text-[#22C55E]">
          <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>LIVE
        </span>
      </div>

      <%!-- Body --%>
      <div class="relative z-10 px-3 pt-2.5 pb-1.5 flex-1 flex flex-col min-h-0">
        <div class="flex items-center justify-between gap-2">
          <span class="inline-flex items-center gap-[7px] min-w-0">
            <span
              class="w-1.5 h-1.5 rounded-full shrink-0"
              style={"background:#{RtChartHelpers.group_hex(@bot)};box-shadow:0 0 0 2px #{RtChartHelpers.group_hex(@bot)}25;"}
            >
            </span>
            <span class="bw-display text-[13px] font-semibold text-[#E8E4DD] tracking-[-0.01em] truncate leading-none">
              {RtChartHelpers.bot_name(@bot)}
            </span>
          </span>
          <span
            class="bw-display text-[9px] font-semibold uppercase tracking-[0.15em] px-1.5 py-0.5 rounded-[3px] leading-none"
            style={"color:#{RtChartHelpers.group_hex(@bot)};background:#{RtChartHelpers.group_hex(@bot)}20;"}
          >
            {RtChartHelpers.group_label(@bot)}
          </span>
        </div>

        <div class="flex items-baseline justify-between gap-2 mt-2">
          <span class="bw-mono text-[14px] font-medium text-[#E8E4DD]">
            {RtChartHelpers.format_price(@bot && @bot["bid_price"])}<span class="text-[#6B7280] opacity-60 mx-0.5">/</span>{RtChartHelpers.format_price(@bot && @bot["ask_price"])}
          </span>
          <span
            class="bw-mono text-[12px] font-semibold px-1.5 py-0.5 rounded leading-tight"
            style={"color:#{RtChartHelpers.change_color(@change)};background:#{RtChartHelpers.change_bg(@change)};"}
          >
            {RtChartHelpers.format_change(@change)}
          </span>
        </div>

        <div class="bw-display text-[9px] font-semibold uppercase tracking-[0.1em] text-[#4B5563] mt-0.5">
          SOL · {RtChartHelpers.tf_label(@tf)}
        </div>

        <%!-- Sparkline --%>
        <div
          id={"widget-#{@banner.id}-canvas-wrapper"}
          phx-update="ignore"
          class="relative flex-1 min-h-0 mt-2 -mx-0.5"
        >
          <div
            data-role="rt-square-canvas"
            class="w-full h-full"
          ></div>
          <script
            type="application/json"
            data-role="rt-square-seed"
          ><%= Phoenix.HTML.raw(@points_json) %></script>
        </div>
      </div>

      <%!-- Footer --%>
      <div class="relative z-10 h-[24px] px-2.5 flex items-center justify-between border-t border-white/[0.06] shrink-0">
        <span class="bw-display inline-flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-[0.14em] text-[#9CA3AF]">
          <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>AI Trading Bot
        </span>
        <span class="bw-display text-[10px] font-medium text-[#E8E4DD] tracking-[0.02em]">
          view →
        </span>
      </div>
    </div>
    """
  end
end
