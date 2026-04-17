defmodule BlocksterV2Web.Widgets.RtChartPortrait do
  @moduledoc """
  RogueTrader portrait chart widget (440 × 640, mobile full × 600).

  Vertical variant of `rt_chart_landscape` — bot meta + price stacked
  above a full-width row of timeframe pills, with the chart filling the
  remaining vertical space. Shares the `RtChartWidget` JS hook so the
  lightweight-charts Area series and click/pill wiring behave exactly
  the same as the landscape widget.

  Plan: docs/solana/realtime_widgets_plan.md · §F `rt_chart_portrait`
  Mock: docs/solana/widgets_mocks/rt_chart_portrait_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.RtChartHelpers

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :selection, :any, default: nil
  attr :chart_data, :map, default: %{}
  attr :tracker_error?, :boolean, default: false

  def rt_chart_portrait(assigns) do
    tf = RtChartHelpers.resolve_tf(assigns.selection)
    bot = RtChartHelpers.resolve_bot(assigns.bots, assigns.selection)
    points = RtChartHelpers.resolve_points(assigns.chart_data, assigns.selection)
    change = RtChartHelpers.change_for(bot, tf)
    hl = RtChartHelpers.high_low(points)

    assigns =
      assigns
      |> assign(:bot, bot)
      |> assign(:tf, tf)
      |> assign(:points_json, RtChartHelpers.points_as_json(points))
      |> assign(:change, change)
      |> assign(:hl, hl)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell relative w-full max-w-[440px] mx-auto flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD] bw-shell-bg-grid"
      style="min-height:640px;"
      phx-hook="RtChartWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_chart_portrait"
      data-bot-id={RtChartHelpers.bot_slug(@bot)}
      data-tf={@tf}
      data-change-pct={if is_number(@change), do: Float.to_string(@change * 1.0), else: ""}
    >
      <%!-- Header strip --%>
      <div class="relative z-10 flex items-center gap-3 px-5 pt-4 pb-3 border-b border-white/[0.06]">
        <span class="relative inline-flex shrink-0" style="line-height:1;">
          <img
            class="h-[26px] w-auto block"
            src="https://ik.imagekit.io/blockster/rogue-logo-white.png"
            alt="Rogue Trader"
          />
          <span
            class="bw-mono"
            style="position:absolute;bottom:-4px;right:0;font-weight:700;font-size:9px;color:#22C55E;letter-spacing:0.3em;line-height:1;"
          >
            TRADER
          </span>
        </span>
        <span class="w-px h-[10px] bg-white/[0.10]"></span>
        <span class="bw-display text-[10px] uppercase tracking-[0.18em] text-[#4B5563] font-medium">
          TRACKING {RtChartHelpers.bot_name(@bot)}
        </span>
        <span class="flex-1"></span>
        <span class="bw-display inline-flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.12em] text-[#22C55E]">
          <span class="bw-pulse-dot"></span>LIVE
        </span>
      </div>

      <%!-- Body: single column, chart fills remaining height --%>
      <div class="relative z-10 p-3.5 flex-1 flex flex-col min-h-0">
        <div class="bw-card flex-1 flex flex-col px-5 pt-5 pb-4 min-h-0">
          <%!-- Stacked header --%>
          <div class="mb-3.5">
            <div class="inline-flex items-center gap-1.5 mb-0.5">
              <span
                class="w-1.5 h-1.5 rounded-full"
                style={"background:#{RtChartHelpers.group_hex(@bot)};box-shadow:0 0 0 2px #{RtChartHelpers.group_hex(@bot)}25;"}
              >
              </span>
              <span class="bw-display text-[11px] font-medium text-[#6B7280]">
                {RtChartHelpers.bot_name(@bot)}-LP Price
              </span>
              <span class="text-[#4B5563] text-[10px]">·</span>
              <span
                class="bw-display text-[9px] font-semibold uppercase tracking-[0.16em]"
                style={"color:#{RtChartHelpers.group_hex(@bot)};"}
              >
                {RtChartHelpers.group_label(@bot)}
              </span>
            </div>

            <div class="flex items-baseline gap-2 flex-wrap mt-0.5">
              <span class="bw-mono text-[26px] font-medium text-[#E8E4DD] leading-[1.1]">
                {RtChartHelpers.format_price(@bot && @bot["bid_price"])}<span class="text-[#6B7280] opacity-60 mx-0.5">/</span>{RtChartHelpers.format_price(@bot && @bot["ask_price"])}
              </span>
              <span class="text-[#6B7280] text-[13px] font-medium tracking-[0.04em]">SOL</span>
              <span
                class="bw-mono text-[17px] font-semibold px-2 py-0.5 rounded-[5px]"
                style={"color:#{RtChartHelpers.change_color(@change)};background:#{RtChartHelpers.change_bg(@change)};"}
              >
                {RtChartHelpers.format_change(@change)}
              </span>
            </div>

            <%= if @hl do %>
              <div class="bw-mono text-[11px] text-[#6B7280] mt-2 inline-flex items-center gap-1">
                <span class="text-[#4B5563]">H</span>
                <span class="text-[#22C55E]">{RtChartHelpers.format_price(@hl.high)}</span>
                <span class="text-[#4B5563] mx-1">/</span>
                <span class="text-[#4B5563]">L</span>
                <span class="text-[#EF4444]">{RtChartHelpers.format_price(@hl.low)}</span>
              </div>
            <% end %>
          </div>

          <%!-- Full-width pill row --%>
          <div class="flex gap-[3px] p-1 bg-white/[0.05] border border-white/[0.06] rounded-[10px] mb-3.5">
            <span
              :for={tf_option <- RtChartHelpers.timeframes()}
              class={[
                "flex-1 text-center py-1.5 rounded-[6px] text-[11px] font-medium tracking-[0.02em] leading-tight cursor-pointer select-none",
                if(tf_option == @tf,
                  do: "rt-tf--active bg-white/10 text-[#E8E4DD] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)]",
                  else: "text-[#6B7280] hover:text-[#E8E4DD]")
              ]}
              data-role="rt-chart-tf"
              data-tf={tf_option}
            >
              {RtChartHelpers.tf_label(tf_option)}
            </span>
          </div>

          <%!-- Chart fills remaining --%>
          <div
            id={"widget-#{@banner.id}-canvas-wrapper"}
            phx-update="ignore"
            class="relative w-full flex-1 min-h-0"
            style="min-height:320px;"
          >
            <div
              data-role="rt-chart-canvas"
              class="w-full h-full"
              style="min-height:320px;"
            ></div>
            <script
              type="application/json"
              data-role="rt-chart-seed"
            ><%= Phoenix.HTML.raw(@points_json) %></script>
          </div>
        </div>
      </div>

      <%!-- Footer --%>
      <div class="relative z-10 flex items-center justify-between gap-4 px-5 py-3.5 border-t border-white/[0.06]">
        <span class="bw-display text-[12px] font-medium text-[#9CA3AF] leading-snug">
          {RtChartHelpers.bot_name(@bot)} is a Solana-powered AI trading bot.
        </span>
        <span class="bw-display text-[12px] font-semibold text-[#E8E4DD] whitespace-nowrap">
          Deposit SOL →
        </span>
      </div>
    </div>
    """
  end
end
