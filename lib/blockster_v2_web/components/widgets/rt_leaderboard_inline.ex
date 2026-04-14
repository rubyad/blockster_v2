defmodule BlocksterV2Web.Widgets.RtLeaderboardInline do
  @moduledoc """
  RogueTrader inline leaderboard (full × ~480, mobile full × auto).

  Renders the top 10 bots (by `lp_price` desc) in a desktop table:
  rank · bot name + group tag · LP bid/ask · 1h · 24h · AUM. Mobile
  collapses to a 2-column compact card grid. Header: "Top RogueBots"
  + LIVE pill. Footer tagline + "View all AI Bots →" CTA.

  Per-row clicks route to `/bot/:slug` (Decision #7 exception). The
  `RtLeaderboardWidget` JS hook wires each row's `click` listener and
  pushes `widget_click` with a nested `{bot_id, tf: "7d"}` subject so
  the existing `WidgetEvents` macro + `ClickRouter` handle the
  RogueTrader redirect without ambiguity with FateSwap `order_id`
  routing. The footer CTA uses a flat `phx-click` with `subject="rt"`
  to land on the RogueTrader homepage.

  Plan: docs/solana/realtime_widgets_plan.md · §F `rt_leaderboard_inline`
  Mock: docs/solana/widgets_mocks/rt_leaderboard_inline_mock.html
  """

  use Phoenix.Component

  @max_rows 10

  attr :banner, :map, required: true
  attr :bots, :list, default: []

  def rt_leaderboard_inline(assigns) do
    bots = assigns.bots |> sort_bots() |> Enum.take(@max_rows)

    assigns = assign(assigns, :bots, bots)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell relative w-full flex flex-col overflow-hidden text-[#E8E4DD] bw-shell-bg-grid"
      phx-hook="RtLeaderboardWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_leaderboard_inline"
    >
      <%!-- Header --%>
      <div class="relative z-[1] px-5 pt-4 pb-3 flex items-center gap-3 border-b border-white/[0.06]">
        <span class="relative inline-flex shrink-0" style="line-height:1;">
          <img
            class="h-[26px] w-auto block"
            src="https://ik.imagekit.io/blockster/rogue-logo-white.png"
            alt="Rogue Trader"
          />
          <span
            class="bw-mono"
            style="position:absolute;bottom:-5px;right:0;font-weight:700;font-size:9px;color:#22C55E;letter-spacing:0.3em;line-height:1;"
          >
            TRADER
          </span>
        </span>
        <span class="w-px h-[10px] bg-white/[0.10]"></span>
        <span class="bw-display text-[12px] font-semibold text-[#E8E4DD] tracking-[0.02em]">
          Top RogueBots
        </span>
        <span class="flex-1"></span>
        <span class="bw-display inline-flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.12em] text-[#22C55E]">
          <span class="bw-pulse-dot" style="width:5px;height:5px;"></span>LIVE
        </span>
      </div>

      <%!-- Body: desktop table + mobile card grid --%>
      <div class="relative z-[1] px-2 md:px-4 py-2 md:py-3" data-role="rt-lb-body">
        <%= if @bots == [] do %>
          <div class="px-4 py-10 text-center">
            <div class="bw-display text-[10px] uppercase tracking-[0.14em] text-[#6B7280] mb-1">
              Loading roguebots
            </div>
            <div class="bw-display text-[11px] text-[#4B5563]">
              Ranked bot list populates once data arrives.
            </div>
          </div>
        <% else %>
          <%!-- Desktop table --%>
          <table class="w-full border-collapse hidden md:table">
            <thead>
              <tr>
                <th class="text-left bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold pl-2 pr-2 pt-2 pb-2 border-b border-white/[0.06]">#</th>
                <th class="text-left bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold px-2 pt-2 pb-2 border-b border-white/[0.06]">Bot</th>
                <th class="text-right bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold px-2 pt-2 pb-2 border-b border-white/[0.06] whitespace-nowrap">LP Bid / Ask</th>
                <th class="text-right bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold px-2 pt-2 pb-2 border-b border-white/[0.06]">1h</th>
                <th class="text-right bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold px-2 pt-2 pb-2 border-b border-white/[0.06]">24h</th>
                <th class="text-right bw-display text-[10px] uppercase tracking-[0.12em] text-[#6B7280] font-semibold px-2 pt-2 pb-2 border-b border-white/[0.06]">AUM</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{bot, idx} <- Enum.with_index(@bots, 1)}
                class="bw-lb-row border-b border-white/[0.03] last:border-b-0"
                data-role="rt-lb-row"
                data-bot-id={bot_slug(bot)}
              >
                <td class="bw-mono text-[11px] text-[#6B7280] px-2 py-2 w-[40px]">
                  {idx}
                </td>
                <td class="px-2 py-2 min-w-[180px]">
                  <span class="bw-display block text-[13px] font-bold text-[#E8E4DD] tracking-[0.01em] mb-0.5">
                    {bot_name(bot)}
                  </span>
                  <span class="inline-flex items-center gap-1.5 text-[11px] text-[#6B7280]">
                    <span
                      class="bw-display text-[9px] font-semibold uppercase tracking-[0.1em] px-1.5 py-[2px] rounded leading-none"
                      style={"color:#{group_hex(bot)};background:#{group_hex(bot)}20;"}
                    >
                      {group_label(bot)}
                    </span>
                    <span :if={archetype(bot)} class="text-[#9CA3AF] text-[11px]">
                      {archetype(bot)}
                    </span>
                  </span>
                </td>
                <td class="px-2 py-2 text-right bw-mono text-[12px] whitespace-nowrap">
                  <span class="text-[#22C55E]">{format_price(bot["bid_price"] || bot["lp_price"])}</span><span class="text-[#6B7280] opacity-50 mx-0.5">/</span><span class="text-[#EF4444]">{format_price(bot["ask_price"] || bot["lp_price"])}</span>
                </td>
                <td class={[
                  "px-2 py-2 text-right bw-mono text-[11px] font-semibold",
                  change_text_class(change_1h(bot))
                ]}>
                  {format_change(change_1h(bot))}
                </td>
                <td class={[
                  "px-2 py-2 text-right bw-mono text-[11px] font-semibold",
                  change_text_class(change_24h(bot))
                ]}>
                  {format_change(change_24h(bot))}
                </td>
                <td class="px-2 py-2 text-right">
                  <span class="bw-mono text-[12px] text-[#9CA3AF]">{format_aum(bot)}</span>
                  <span class="bw-display text-[10px] text-[#6B7280] ml-1">SOL</span>
                </td>
              </tr>
            </tbody>
          </table>

          <%!-- Mobile 2-column grid --%>
          <div class="grid grid-cols-2 gap-2 md:hidden p-2">
            <div
              :for={{bot, idx} <- Enum.with_index(@bots, 1)}
              class="bw-lb-row bw-card px-3 py-2.5 flex flex-col gap-1"
              data-role="rt-lb-row"
              data-bot-id={bot_slug(bot)}
            >
              <div class="flex items-center justify-between gap-1.5">
                <span class="inline-flex items-center gap-1.5 min-w-0">
                  <span
                    class="w-1.5 h-1.5 rounded-full shrink-0"
                    style={"background:#{group_hex(bot)};"}
                  >
                  </span>
                  <span class="bw-mono text-[9px] text-[#4B5563] tracking-wider">
                    #{idx}
                  </span>
                  <span class="bw-display font-bold text-[12px] text-[#E8E4DD] tracking-[0.01em] truncate">
                    {bot_name(bot)}
                  </span>
                </span>
              </div>
              <span class="bw-mono text-[11px] text-[#9CA3AF]">
                {format_price(bot["bid_price"] || bot["lp_price"])} / {format_price(bot["ask_price"] || bot["lp_price"])}
              </span>
              <span class={[
                "bw-mono text-[10px] font-semibold rounded px-1.5 py-[2px] inline-flex items-center gap-0.5 self-start",
                change_pill_class(change_24h(bot))
              ]}>
                <span class="text-[8px] -translate-y-[0.5px]">{change_arrow(change_24h(bot))}</span>{format_change(change_24h(bot))}
              </span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Footer --%>
      <div
        class="relative z-[1] px-5 py-3.5 flex items-center justify-between gap-4 border-t border-white/[0.06] cursor-pointer hover:bg-white/[0.02] transition-colors"
        data-role="rt-lb-footer"
        phx-click="widget_click"
        phx-value-banner_id={@banner.id}
        phx-value-subject="rt"
      >
        <span class="bw-display text-[13px] text-[#9CA3AF] font-medium leading-snug">
          30 AI trading bots. Live on Solana.
        </span>
        <span class="bw-display text-[12px] font-semibold text-[#E8E4DD] whitespace-nowrap">
          View all AI Bots →
        </span>
      </div>
    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp sort_bots(bots) when is_list(bots) do
    Enum.sort_by(bots, fn b -> -(to_float(b["lp_price"]) || 0.0) end)
  end

  defp sort_bots(_), do: []

  defp to_float(x) when is_number(x), do: x * 1.0
  defp to_float(_), do: nil

  defp bot_name(bot) do
    (bot["name"] || bot["slug"] || bot["bot_id"] || "")
    |> to_string()
    |> String.upcase()
  end

  defp bot_slug(bot), do: bot["slug"] || bot["bot_id"] || ""

  defp group_key(bot) do
    (bot["group_name"] || bot["group_id"] || "")
    |> to_string()
    |> String.downcase()
  end

  defp group_label(bot), do: bot |> group_key() |> String.upcase()

  defp group_hex(bot) do
    case group_key(bot) do
      "crypto" -> "#3B82F6"
      "equities" -> "#10B981"
      "indexes" -> "#8B5CF6"
      "commodities" -> "#F59E0B"
      "forex" -> "#F43F5E"
      _ -> "#6B7280"
    end
  end

  defp archetype(bot), do: bot["archetype"]

  defp format_price(nil), do: "—"

  defp format_price(val) when is_number(val) do
    :io_lib.format("~.4f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_price(_), do: "—"

  defp format_aum(bot) do
    case bot["sol_balance_ui"] || bot["sol_balance"] do
      nil -> "—"
      val when is_number(val) -> :io_lib.format("~.2f", [val * 1.0]) |> IO.iodata_to_binary()
      _ -> "—"
    end
  end

  defp change_1h(bot), do: bot["lp_price_change_1h_pct"]
  defp change_24h(bot), do: bot["lp_price_change_24h_pct"]

  defp change_text_class(v) when is_number(v) and v >= 0, do: "text-[#22C55E]"
  defp change_text_class(v) when is_number(v), do: "text-[#EF4444]"
  defp change_text_class(_), do: "text-[#6B7280]"

  defp change_pill_class(v) when is_number(v) and v >= 0,
    do: "text-[#22C55E] bg-[#22C55E]/10"

  defp change_pill_class(v) when is_number(v),
    do: "text-[#EF4444] bg-[#EF4444]/10"

  defp change_pill_class(_), do: "text-[#6B7280] bg-white/[0.04]"

  defp change_arrow(v) when is_number(v) and v >= 0, do: "▲"
  defp change_arrow(v) when is_number(v), do: "▼"
  defp change_arrow(_), do: "·"

  defp format_change(nil), do: "—"

  defp format_change(v) when is_number(v) do
    sign = if v >= 0, do: "+", else: "−"
    mag = :io_lib.format("~.2f", [abs(v) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}#{mag}%"
  end

  defp format_change(_), do: "—"
end
