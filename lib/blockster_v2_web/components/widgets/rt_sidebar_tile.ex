defmodule BlocksterV2Web.Widgets.RtSidebarTile do
  @moduledoc """
  RogueTrader sidebar tile (200 × 340) — taller sibling of
  `rt_square_compact` sized to match the height of Blockster's article-page
  discover-card sidebar boxes. Adds an H/L row and a larger sparkline.

  Reuses the `RtSquareCompactWidget` JS hook — same data seed pattern
  (`data-role="rt-square-seed"` + `data-role="rt-square-canvas"`), just a
  taller canvas wrapper so the sparkline has more vertical room.

  Plan: docs/solana/realtime_widgets_plan.md · §F `rt_sidebar_tile`
  Mock: docs/solana/widgets_mocks/rt_sidebar_tile_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.RtChartHelpers

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :selection, :any, default: nil
  attr :chart_data, :map, default: %{}
  attr :tracker_error?, :boolean, default: false

  def rt_sidebar_tile(assigns) do
    tf = RtChartHelpers.resolve_tf(assigns.selection)
    bot = RtChartHelpers.resolve_bot(assigns.bots, assigns.selection)
    points = RtChartHelpers.resolve_points(assigns.chart_data, assigns.selection)
    change = RtChartHelpers.change_for(bot, tf)
    high_low = RtChartHelpers.high_low(points)

    assigns =
      assigns
      |> assign(:bot, bot)
      |> assign(:tf, tf)
      |> assign(:points_json, RtChartHelpers.points_as_json(points))
      |> assign(:change, change)
      |> assign(:high_low, high_low)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell relative w-[200px] h-[340px] flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="RtSquareCompactWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_sidebar_tile"
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
      <div class="relative z-10 px-3 pt-3 pb-2 flex-1 flex flex-col min-h-0">
        <div class="flex items-center justify-between gap-2">
          <span class="inline-flex items-center gap-[7px] min-w-0">
            <span
              class="w-1.5 h-1.5 rounded-full shrink-0"
              style={"background:#{RtChartHelpers.group_hex(@bot)};box-shadow:0 0 0 2px #{RtChartHelpers.group_hex(@bot)}25;"}
            >
            </span>
            <span class="bw-display text-[14px] font-semibold text-[#E8E4DD] tracking-[-0.01em] truncate leading-none">
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

        <div class="flex items-baseline justify-between gap-1 mt-3">
          <span class="bw-mono text-[11px] font-medium text-[#E8E4DD] whitespace-nowrap">
            {RtChartHelpers.format_price(@bot && @bot["bid_price"])}<span class="text-[#6B7280] opacity-60 mx-0.5">/</span>{RtChartHelpers.format_price(@bot && @bot["ask_price"])}
          </span>
          <span
            class="bw-mono text-[11px] font-semibold px-1 py-0.5 rounded leading-tight shrink-0 whitespace-nowrap"
            style={"color:#{RtChartHelpers.change_color(@change)};background:#{RtChartHelpers.change_bg(@change)};margin-right:6px;"}
          >
            {RtChartHelpers.format_change(@change)}
          </span>
        </div>

        <div class="bw-display text-[9px] font-semibold uppercase tracking-[0.1em] text-[#4B5563] mt-1">
          SOL · {RtChartHelpers.tf_label(@tf)}
        </div>

        <%!-- H/L row --%>
        <div class="bw-mono inline-flex items-center gap-[3px] text-[10px] text-[#6B7280] leading-none mt-2.5">
          <span class="text-[#4B5563]">H</span>
          <span class="text-[#22C55E]">{RtChartHelpers.format_price(@high_low && @high_low.high)}</span>
          <span class="text-[#4B5563] mx-1.5">/</span>
          <span class="text-[#4B5563]">L</span>
          <span class="text-[#EF4444]">{RtChartHelpers.format_price(@high_low && @high_low.low)}</span>
        </div>

        <%!-- Sparkline (taller than rt_square_compact) --%>
        <div
          id={"widget-#{@banner.id}-canvas-wrapper"}
          phx-update="ignore"
          class="relative flex-1 min-h-0 mt-1 -mx-0.5"
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
      <div class="relative z-10 h-[28px] px-2.5 flex items-center justify-between border-t border-white/[0.06] shrink-0">
        <span class="bw-display inline-flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-[0.14em] text-[#9CA3AF]">
          <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>AI Trading Bot
        </span>
        <span class="bw-display text-[10px] font-medium text-[#E8E4DD] tracking-[0.02em]">
          Deposit SOL →
        </span>
      </div>
    </div>
    """
  end
end
