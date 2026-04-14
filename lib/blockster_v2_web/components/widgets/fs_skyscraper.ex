defmodule BlocksterV2Web.Widgets.FsSkyscraper do
  @moduledoc """
  FateSwap live-trade skyscraper widget (200 × 760).

  Renders a dark "SOLANA DEX" trading terminal card: header with FateSwap
  logo + brand-gradient tagline, a scrollable feed of up to 20 recent
  trades (newest on top), and an "Open FateSwap" footer CTA. The entire
  card is the click target — `phx-click="widget_click"` bubbles to the
  host LiveView's `WidgetEvents` macro which handles click counting and
  the external redirect to `fateswap.io`.

  Copy is deliberately third-person ("Trader Received / Trader Paid") per
  the Phase 0 locked-in design decisions.

  Plan: docs/solana/realtime_widgets_plan.md · §F, `fs_skyscraper`
  Mock: docs/solana/realtime_widgets_mock.html lines 373–636 (left widget)
  """

  use Phoenix.Component

  @max_rows 20

  attr :banner, :map, required: true
  attr :trades, :list, default: []

  def fs_skyscraper(assigns) do
    assigns = assign(assigns, :trades, Enum.take(assigns.trades || [], @max_rows))

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell flex flex-col w-[200px] h-[760px] cursor-pointer text-[#E8E4DD]"
      phx-hook="FsSkyscraperWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_skyscraper"
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject="fs"
    >
      <%!-- Header --%>
      <div class="px-3 pt-3 pb-2.5 border-b border-white/[0.05] bg-gradient-to-b from-white/[0.025] to-transparent shrink-0">
        <div class="flex items-center justify-between">
          <img
            src="https://fateswap.io/images/logo-full.svg"
            alt="FateSwap"
            class="h-[18px] w-auto block"
          />
          <div class="flex items-center gap-1 bg-[#22C55E]/10 border border-[#22C55E]/30 rounded px-1.5 py-[2px]">
            <div class="relative w-1.5 h-1.5">
              <div class="absolute inset-0 bg-[#22C55E] rounded-full bw-pulse-dot"></div>
              <div class="absolute inset-0 bg-[#22C55E] rounded-full bw-pulse-ring"></div>
            </div>
            <span class="bw-display text-[8px] font-semibold tracking-[0.1em] text-[#4ade80]">LIVE</span>
          </div>
        </div>
        <div class="mt-2 flex items-center justify-between">
          <span class="bw-display text-[9px] font-extrabold tracking-[0.14em] uppercase text-[#E8E4DD]">
            Solana&nbsp;DEX
          </span>
        </div>
        <div class="mt-1.5">
          <div
            class="bw-display font-extrabold text-[13px] leading-[1.15]"
            style="letter-spacing:-0.005em;background:linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;"
          >
            Gamble for a better price than market
          </div>
        </div>
      </div>

      <%!-- Trades scroll body --%>
      <div
        class="bw-scroll bw-shell-bg-grid flex-1 overflow-y-auto"
        data-role="fs-skyscraper-body"
      >
        <%= if @trades == [] do %>
          <div class="h-full w-full grid place-items-center px-3 py-8 text-center">
            <div>
              <div class="bw-display text-[9px] uppercase tracking-[0.14em] text-[#6B7280] mb-1">
                Waiting for trades
              </div>
              <div class="bw-display text-[10px] text-[#4B5563] leading-snug">
                Live feed starts once FateSwap settles its next order.
              </div>
            </div>
          </div>
        <% else %>
          <div class="divide-y divide-white/[0.04]">
            <div
              :for={trade <- @trades}
              class={[
                "px-2.5 py-2 relative transition-colors duration-200",
                trade_stripe(trade),
                "bg-[#14141A] hover:bg-[#1c1c25]"
              ]}
              data-trade-id={trade["id"]}
            >
              <div class="flex items-center justify-between mb-1 gap-1">
                <div class="flex items-center gap-1 min-w-0">
                  <img
                    :if={trade["token_logo_url"]}
                    src={trade["token_logo_url"]}
                    alt={trade["token_symbol"] || ""}
                    class="w-[14px] h-[14px] rounded-full bg-[#1f1f28] object-cover block shrink-0"
                    onerror="this.style.display='none'"
                  />
                  <span class={[
                    "bw-display text-[9px] leading-none",
                    side_arrow_color(trade)
                  ]}>
                    {side_arrow(trade)}
                  </span>
                  <span class={[
                    "bw-display font-bold text-[9px] tracking-wider",
                    side_label_color(trade)
                  ]}>
                    {side_label(trade)}
                  </span>
                </div>
                <span class={[
                  "bw-display shrink-0 inline-block rounded text-[7.5px] font-semibold uppercase tracking-[0.08em] px-1 py-[2px] border",
                  status_pill_class(trade)
                ]}>
                  {trade["status_text"] || status_fallback(trade)}
                </span>
              </div>

              <div class="bw-mono text-[10px] text-[#E8E4DD] mb-0.5 leading-snug flex items-center gap-1">
                <span>{format_bid(trade)}</span>
                <span class="text-[#4B5563]">→</span>
                <span class={ask_color(trade)}>{format_ask(trade)}</span>
              </div>

              <div class="flex items-center gap-1 mb-1">
                <span class="bw-display text-[7px] uppercase tracking-[0.1em] text-[#6B7280]">
                  {discount_label(trade)}
                </span>
                <span class="bw-mono text-[9px] font-semibold text-[#facc15]">
                  {format_discount(trade)}
                </span>
                <span :if={trade["multiplier"]} class="text-[#4B5563] text-[7px]">·</span>
                <span :if={trade["multiplier"]} class="bw-mono text-[8.5px] text-[#9CA3AF]">
                  ×{format_multiplier(trade["multiplier"])}
                </span>
              </div>

              <div class="flex items-baseline justify-between mb-0.5">
                <span class={[
                  "bw-mono text-[10.5px] font-semibold",
                  profit_color(trade)
                ]}>
                  {format_profit_sol(trade)}
                </span>
                <span class="bw-mono text-[8.5px] text-[#6B7280]">
                  {format_profit_usd(trade)}
                </span>
              </div>

              <div class="flex items-center justify-between mt-1">
                <span class="bw-mono text-[8px] text-[#4B5563]">
                  {wallet_label(trade)}
                </span>
                <span class="bw-mono text-[8px] text-[#4B5563]">
                  {relative_time(trade["settled_at"])}
                </span>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Tagline + footer link --%>
      <div class="border-t border-white/[0.05] shrink-0">
        <p class="px-3 pt-2.5 pb-2 bw-display text-[10px] text-[#9CA3AF] leading-[1.45]">
          Trader Received / Trader Paid per settled order. Gamble for a better price than market.
        </p>
        <div class="block px-3 pb-2.5 group">
          <div class="flex items-center justify-between">
            <span class="bw-display text-[8px] font-semibold tracking-[0.14em] text-[#6B7280] uppercase">
              Open FateSwap
            </span>
            <span class="text-[#6B7280] text-[10px]">→</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp trade_stripe(%{"filled" => true}), do: "shadow-[inset_2px_0_0_#22C55E]"
  defp trade_stripe(%{"filled" => false}), do: "shadow-[inset_2px_0_0_#EF4444]"
  defp trade_stripe(_), do: ""

  defp side_arrow(%{"side" => "sell"}), do: "▼"
  defp side_arrow(_), do: "▲"

  defp side_arrow_color(%{"side" => "sell"}), do: "text-[#EF4444]"
  defp side_arrow_color(_), do: "text-[#22C55E]"

  defp side_label_color(%{"side" => "sell"}), do: "text-[#f87171]"
  defp side_label_color(_), do: "text-[#4ade80]"

  defp side_label(trade) do
    side =
      case trade["side"] do
        "sell" -> "SELL"
        _ -> "BUY"
      end

    symbol = trade["token_symbol"] || "TOKEN"
    "#{side} #{symbol}"
  end

  defp status_pill_class(%{"status_text" => "ORDER FILLED"}),
    do: "bg-[#22C55E]/13 text-[#4ade80] border-[#22C55E]/30"

  defp status_pill_class(%{"status_text" => "DISCOUNT FILLED"}),
    do: "bg-[#22C55E]/13 text-[#4ade80] border-[#22C55E]/30"

  defp status_pill_class(%{"status_text" => "NOT FILLED"}),
    do: "bg-[#EF4444]/13 text-[#f87171] border-[#EF4444]/30"

  defp status_pill_class(%{"filled" => true}),
    do: "bg-[#22C55E]/13 text-[#4ade80] border-[#22C55E]/30"

  defp status_pill_class(_), do: "bg-[#EF4444]/13 text-[#f87171] border-[#EF4444]/30"

  defp status_fallback(%{"filled" => true}), do: "FILLED"
  defp status_fallback(_), do: "NOT FILLED"

  defp format_bid(trade) do
    format_price(trade["sol_amount_ui"] || trade["sol_amount"])
  end

  defp format_ask(trade) do
    format_price(trade["payout_ui"] || trade["payout"])
  end

  defp ask_color(%{"filled" => true}), do: "text-[#4ade80]"
  defp ask_color(_), do: "text-[#4B5563]"

  defp format_price(nil), do: "—"

  defp format_price(val) when is_number(val) do
    :io_lib.format("~.4f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_price(_), do: "—"

  defp discount_label(%{"side" => "sell"}), do: "Premium"
  defp discount_label(_), do: "Discount"

  defp format_discount(%{"discount_pct" => pct}) when is_number(pct) do
    :io_lib.format("~.1f%", [abs(pct) * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_discount(_), do: "—"

  defp format_multiplier(val) when is_number(val) do
    :io_lib.format("~.2f", [val * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_multiplier(_), do: "1.00"

  defp profit_color(%{"filled" => true}), do: "text-[#4ade80]"
  defp profit_color(%{"filled" => false}), do: "text-[#f87171]"
  defp profit_color(_), do: "text-[#9CA3AF]"

  defp format_profit_sol(%{"profit_ui" => ui, "filled" => filled})
       when is_number(ui) do
    sign =
      cond do
        filled == false -> "−"
        ui >= 0 -> "+"
        true -> "−"
      end

    magnitude = :io_lib.format("~.2f", [abs(ui) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}#{magnitude} SOL"
  end

  defp format_profit_sol(_), do: "—"

  defp format_profit_usd(%{"profit_usd" => usd}) when is_number(usd) do
    :io_lib.format("$~.2f", [abs(usd) * 1.0]) |> IO.iodata_to_binary()
  end

  defp format_profit_usd(_), do: ""

  defp wallet_label(%{"wallet_truncated" => w}) when is_binary(w) and w != "", do: w

  defp wallet_label(%{"wallet_address" => w}) when is_binary(w) and byte_size(w) > 9 do
    "#{binary_part(w, 0, 4)}…#{binary_part(w, byte_size(w) - 4, 4)}"
  end

  defp wallet_label(_), do: ""

  defp relative_time(nil), do: "just now"

  defp relative_time(ts) when is_integer(ts) do
    now = System.system_time(:second)
    delta = max(0, now - ts)

    cond do
      delta < 60 -> "#{delta}s ago"
      delta < 3600 -> "#{div(delta, 60)}m ago"
      delta < 86_400 -> "#{div(delta, 3600)}h ago"
      true -> "#{div(delta, 86_400)}d ago"
    end
  end

  defp relative_time(%DateTime{} = dt), do: relative_time(DateTime.to_unix(dt))
  defp relative_time(_), do: ""
end
