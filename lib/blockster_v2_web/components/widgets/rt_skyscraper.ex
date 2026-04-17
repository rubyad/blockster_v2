defmodule BlocksterV2Web.Widgets.RtSkyscraper do
  @moduledoc """
  RogueTrader top-bots skyscraper widget (200 × 696).

  Renders a dark trading terminal card: header with "ROGUE TRADER" logo +
  LIVE pill + "TOP ROGUEBOTS" subtitle, a scrollable feed of up to 30
  bots ranked by `lp_price` desc, and a "Deposit SOL" footer CTA.
  Each bot row includes rank, group dot + tag (CRYPTO / EQUITIES /
  INDEXES / COMMODITIES / FOREX), and a bid / ask / 24H-change grid.
  The CTA is the click target for the whole widget —
  `phx-click="widget_click"` with `subject="rt"` bubbles to the
  `WidgetEvents` macro.

  Prices render with 4 decimal places per the Phase 0 locked-in
  decisions; group tags replace risk tags.

  Plan: docs/solana/realtime_widgets_plan.md · §F, `rt_skyscraper`
  Mock: docs/solana/realtime_widgets_mock.html lines 995–1173 (right widget)
  """

  use Phoenix.Component

  import BlocksterV2Web.Widgets.WidgetShared

  @max_rows 30

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  attr :tracker_error?, :boolean, default: false

  def rt_skyscraper(assigns) do
    assigns =
      assigns
      |> assign(:bots, assigns.bots |> sort_bots() |> Enum.take(@max_rows))

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell flex flex-col w-[200px] h-[696px] cursor-pointer text-[#E8E4DD]"
      phx-hook="RtSkyscraperWidget"
      data-banner-id={@banner.id}
      data-widget-type="rt_skyscraper"
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject="rt"
    >
      <%!-- Header --%>
      <div class="px-3 pt-3 pb-2.5 border-b border-white/[0.05] bg-gradient-to-b from-white/[0.025] to-transparent shrink-0">
        <div class="flex items-center justify-between">
          <div class="relative inline-flex items-center" style="line-height:1;">
            <img
              src="https://ik.imagekit.io/blockster/rogue-logo-white.png"
              alt="Rogue Trader"
              class="h-[22px] w-auto block"
            />
            <span
              class="bw-mono"
              style="position:absolute;bottom:-4px;right:0;font-weight:700;font-size:8px;color:#22C55E;letter-spacing:0.3em;line-height:1;"
            >
              TRADER
            </span>
          </div>
          <div class="flex items-center gap-1 bg-[#22C55E]/10 border border-[#22C55E]/30 rounded px-1.5 py-[2px]">
            <div class="relative w-1.5 h-1.5">
              <div class="absolute inset-0 bg-[#22C55E] rounded-full bw-pulse-dot"></div>
              <div class="absolute inset-0 bg-[#22C55E] rounded-full bw-pulse-ring"></div>
            </div>
            <span class="bw-display text-[8px] font-semibold tracking-[0.1em] text-[#22C55E]">LIVE</span>
          </div>
        </div>
        <div class="mt-2 flex items-center justify-between">
          <span class="bw-display text-[8px] font-semibold tracking-[0.14em] text-[#6B7280]">
            TOP ROGUEBOTS
          </span>
          <span
            class="bw-mono text-[8px] text-[#4B5563]"
            data-role="rt-skyscraper-updated"
          >
            {updated_label(@bots)}
          </span>
        </div>
      </div>

      <%!-- Bots scroll body --%>
      <div class="bw-scroll bw-shell-bg-grid flex-1 overflow-y-auto" data-role="rt-skyscraper-body">
        <%= cond do %>
          <% @bots == [] and @tracker_error? -> %>
            <.tracker_error_placeholder brand={:rt} />
          <% @bots == [] -> %>
            <div class="divide-y divide-white/[0.04]" data-role="rt-skyscraper-skeleton">
              <div :for={_ <- 1..8} class="px-2.5 py-2.5 bg-[#14141A]">
                <div class="flex items-center justify-between mb-1.5">
                  <div class="flex items-center gap-1.5">
                    <.skeleton_bar class="w-4 h-2" />
                    <.skeleton_circle class="w-1.5 h-1.5" />
                    <.skeleton_bar class="w-12 h-2.5" />
                  </div>
                </div>
                <div class="flex items-center justify-between gap-1 mt-1">
                  <.skeleton_bar class="w-12 h-2" />
                  <.skeleton_bar class="w-10 h-2" />
                </div>
                <.skeleton_bar class="w-full h-2 mt-1.5" />
              </div>
            </div>
          <% true -> %>
          <div class="divide-y divide-white/[0.04]">
            <div
              :for={{bot, idx} <- Enum.with_index(@bots, 1)}
              class={[
                "px-2.5 py-2.5 hover:bg-[#1f1f28] transition-colors duration-200 relative",
                if(rem(idx, 2) == 0, do: "bg-[#0a0a0f]", else: "bg-[#1a1a22]")
              ]}
              data-bot-id={bot["bot_id"] || bot["slug"]}
            >
              <div class="flex items-center justify-between mb-1.5">
                <div class="flex items-center gap-1.5">
                  <span class="bw-mono text-[8.5px] text-[#6B7280] font-medium">
                    #{bot["rank"] || idx}
                  </span>
                  <div class={[
                    "w-1.5 h-1.5 rounded-full",
                    group_dot_class(bot)
                  ]}>
                  </div>
                  <span class={[
                    "bw-display inline-block rounded border text-[7.5px] font-semibold uppercase tracking-[0.08em] px-1 py-[1px]",
                    group_tag_class(bot)
                  ]}>
                    {group_label(bot)}
                  </span>
                </div>
              </div>

              <div class="flex items-center justify-between mb-1.5 gap-1">
                <span class="bw-display font-bold text-[12.5px] text-[#E8E4DD] truncate tracking-wide">
                  {bot_name(bot)}
                </span>
              </div>

              <div class="grid grid-cols-3 gap-1">
                <div class="bg-white/[0.025] border border-white/[0.05] rounded px-1 py-1">
                  <div class="bw-display text-[7px] tracking-[0.08em] text-[#6B7280] uppercase leading-none">
                    Bid
                  </div>
                  <div
                    class="bw-mono text-[9.5px] font-semibold text-[#4ade80] leading-tight mt-0.5"
                    data-role="bid"
                  >
                    {format_price(bot["bid_price"] || bot["lp_price"])}
                  </div>
                </div>
                <div class="bg-white/[0.025] border border-white/[0.05] rounded px-1 py-1">
                  <div class="bw-display text-[7px] tracking-[0.08em] text-[#6B7280] uppercase leading-none">
                    Ask
                  </div>
                  <div
                    class="bw-mono text-[9.5px] font-semibold text-[#f87171] leading-tight mt-0.5"
                    data-role="ask"
                  >
                    {format_price(bot["ask_price"] || bot["lp_price"])}
                  </div>
                </div>
                <div class="bg-white/[0.025] border border-white/[0.05] rounded px-1 py-1">
                  <div class="bw-display text-[7px] tracking-[0.08em] text-[#6B7280] uppercase leading-none">
                    24H
                  </div>
                  <div class={[
                    "bw-mono text-[9.5px] font-semibold leading-tight mt-0.5",
                    change_color(bot)
                  ]}>
                    {change_arrow(bot)} {format_change(bot)}
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Tagline + footer link --%>
      <div class="border-t border-white/[0.05] shrink-0">
        <p class="px-3 pt-2.5 pb-2 bw-display text-[10px] text-[#9CA3AF] leading-[1.45]">
          Solana-powered AI agents trading crypto, stocks, forex, commodities.
        </p>
        <div class="block px-3 pb-2.5 group">
          <div class="flex items-center justify-between">
            <span class="bw-display text-[8px] font-semibold tracking-[0.14em] text-[#6B7280] uppercase">
              Deposit SOL
            </span>
            <span class="text-[#6B7280] text-[10px]">→</span>
          </div>
        </div>
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

  defp group_label(bot) do
    (bot["group_name"] || bot["group_id"] || "")
    |> to_string()
    |> String.upcase()
  end

  defp group_key(bot) do
    (bot["group_name"] || bot["group_id"] || "")
    |> to_string()
    |> String.downcase()
  end

  defp group_dot_class(bot) do
    case group_key(bot) do
      "crypto" -> "bg-[#3B82F6]"
      "equities" -> "bg-[#10B981]"
      "indexes" -> "bg-[#8B5CF6]"
      "commodities" -> "bg-[#F59E0B]"
      "forex" -> "bg-[#F43F5E]"
      _ -> "bg-[#6B7280]"
    end
  end

  defp group_tag_class(bot) do
    case group_key(bot) do
      "crypto" -> "bg-[#3B82F6]/13 text-[#60A5FA] border-[#3B82F6]/25"
      "equities" -> "bg-[#10B981]/13 text-[#10B981] border-[#10B981]/25"
      "indexes" -> "bg-[#8B5CF6]/13 text-[#A78BFA] border-[#8B5CF6]/25"
      "commodities" -> "bg-[#F59E0B]/13 text-[#F59E0B] border-[#F59E0B]/25"
      "forex" -> "bg-[#F43F5E]/13 text-[#F43F5E] border-[#F43F5E]/25"
      _ -> "bg-white/[0.04] text-[#9CA3AF] border-white/[0.08]"
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

  defp change_color(bot) do
    case change_value(bot) do
      v when is_number(v) and v >= 0 -> "text-[#4ade80]"
      v when is_number(v) -> "text-[#f87171]"
      _ -> "text-[#6B7280]"
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
        mag = :io_lib.format("~.1f", [abs(v) * 1.0]) |> IO.iodata_to_binary()
        "#{sign}#{mag}%"

      _ ->
        "—"
    end
  end

  defp updated_label([]), do: "—"
  defp updated_label(_), do: "live"
end
