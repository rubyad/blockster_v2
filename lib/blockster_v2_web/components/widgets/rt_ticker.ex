defmodule BlocksterV2Web.Widgets.RtTicker do
  @moduledoc """
  RogueTrader full-width horizontal ticker (full × 56, mobile full × 48).

  CSS-only scrolling marquee of all 30 bots: brand + LIVE pill on the
  left, marquee track in the middle (items duplicated so the
  `translateX(-50%)` loop is seamless), CTA on the right. Each item:
  group dot + bot name + bid (green) / ask (red) + change% pill. Hover
  pauses the scroll via `.bw-marquee:hover` — no JS required for the
  animation itself.

  All-data widget: whole div `phx-click="widget_click"` with flat
  `subject="rt"` bubbles through the `WidgetEvents` macro to the
  project homepage.

  Plan: docs/solana/realtime_widgets_plan.md · §F `rt_ticker`
  Mock: docs/solana/widgets_mocks/rt_ticker_mock.html
  """

  use Phoenix.Component

  import BlocksterV2Web.Widgets.WidgetShared

  @max_items 30

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :tracker_error?, :boolean, default: false

  def rt_ticker(assigns) do
    bots = assigns.bots |> sort_bots() |> Enum.take(@max_items)

    assigns = assign(assigns, :bots, bots)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell bw-ticker relative w-full h-[56px] md:h-[56px] flex items-stretch overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="RtTickerWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_ticker"
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject="rt"
    >
      <%!-- Brand lock-up (sticky left) --%>
      <div class="relative z-[2] shrink-0 flex items-center gap-3 pl-[18px] pr-4 border-r border-white/[0.06] bg-[#0A0A0F]">
        <span class="relative inline-flex" style="line-height:1;">
          <img
            class="h-[26px] w-auto block select-none"
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
        <span class="hidden md:inline-flex items-center gap-1.5 px-2 py-[4px] border border-white/[0.06] rounded-full">
          <span class="relative w-1.5 h-1.5 inline-block">
            <span class="absolute inset-0 bg-[#22C55E] rounded-full bw-pulse-dot"></span>
          </span>
          <span class="bw-display text-[9px] font-semibold tracking-[0.14em] uppercase text-[#22C55E]">
            Live
          </span>
        </span>
      </div>

      <%!-- Marquee --%>
      <div class="bw-marquee" data-role="rt-ticker-marquee">
        <%= cond do %>
          <% @bots == [] and @tracker_error? -> %>
            <div class="flex items-center h-full px-4 gap-2">
              <span class="bw-err-dot"></span>
              <span class="bw-display text-[10px] uppercase tracking-[0.14em] text-[#EAB308]">
                RogueTrader feed paused — retrying
              </span>
            </div>
          <% @bots == [] -> %>
            <div class="flex items-center h-full px-4 gap-3" data-role="rt-ticker-skeleton">
              <div :for={_ <- 1..8} class="flex items-center gap-1.5">
                <.skeleton_circle class="w-1.5 h-1.5" />
                <.skeleton_bar class="w-14 h-3" />
                <.skeleton_bar class="w-10 h-2.5" />
              </div>
            </div>
          <% true -> %>
          <div class="bw-marquee-track" data-role="rt-ticker-track">
            <.rt_ticker_items bots={@bots} />
            <%!-- Duplicated set so the loop is seamless --%>
            <.rt_ticker_items bots={@bots} />
          </div>
        <% end %>
      </div>

      <%!-- Right CTA --%>
      <div class="relative z-[2] shrink-0 hidden md:flex items-center px-[18px] border-l border-white/[0.06] bg-[#0A0A0F]">
        <span class="bw-display text-[11px] font-semibold tracking-[0.02em] text-[#E8E4DD] whitespace-nowrap">
          View all AI Bots →
        </span>
      </div>
    </div>
    """
  end

  attr :bots, :list, required: true

  defp rt_ticker_items(assigns) do
    ~H"""
    <div
      :for={bot <- @bots}
      class="inline-flex items-center gap-[10px] px-[18px] h-full border-r border-white/[0.06] whitespace-nowrap transition-colors duration-150 hover:bg-white/[0.02]"
      data-role="rt-ticker-item"
      data-bot-id={bot["bot_id"] || bot["slug"]}
    >
      <span
        class="w-1.5 h-1.5 rounded-full shrink-0"
        style={"background:#{group_hex(bot)};"}
      >
      </span>
      <span class="bw-display font-bold text-[11px] text-[#E8E4DD] tracking-[0.03em]">
        {bot_name(bot)}
      </span>
      <span class="bw-mono text-[11px] font-medium text-[#9CA3AF] inline-flex items-center gap-0.5">
        <span class="text-[#22C55E]" data-role="bid">{format_price(bot["bid_price"] || bot["lp_price"])}</span>
        <span class="text-[#6B7280] opacity-50 mx-[2px]">/</span>
        <span class="text-[#EF4444]" data-role="ask">{format_price(bot["ask_price"] || bot["lp_price"])}</span>
      </span>
      <span class={[
        "bw-mono text-[11px] font-semibold rounded-[3px] inline-flex items-center gap-0.5 px-1.5 py-[2px] leading-none",
        change_pill_class(bot)
      ]}>
        <span class="text-[9px] leading-none -translate-y-[0.5px]">{change_arrow(bot)}</span>{format_change(bot)}
      </span>
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

  defp group_key(bot) do
    (bot["group_name"] || bot["group_id"] || "")
    |> to_string()
    |> String.downcase()
  end

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

  defp format_price(nil), do: "—"

  defp format_price(val) when is_number(val) do
    :io_lib.format("~.4f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_price(_), do: "—"

  defp change_value(bot) do
    bot["lp_price_change_24h_pct"] || bot["lp_price_change_7d_pct"]
  end

  defp change_pill_class(bot) do
    case change_value(bot) do
      v when is_number(v) and v >= 0 -> "text-[#22C55E] bg-[#22C55E]/10"
      v when is_number(v) -> "text-[#EF4444] bg-[#EF4444]/10"
      _ -> "text-[#6B7280] bg-white/[0.04]"
    end
  end

  defp change_arrow(bot) do
    case change_value(bot) do
      v when is_number(v) and v >= 0 -> "▲"
      v when is_number(v) -> "▼"
      _ -> "·"
    end
  end

  defp format_change(bot) do
    case change_value(bot) do
      v when is_number(v) ->
        sign = if v >= 0, do: "+", else: "−"
        mag = :io_lib.format("~.2f", [abs(v) * 1.0]) |> IO.iodata_to_binary()
        "#{sign}#{mag}%"

      _ ->
        "—"
    end
  end
end
