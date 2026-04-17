defmodule BlocksterV2Web.Widgets.FsSquareCompact do
  @moduledoc """
  FateSwap compact tile (200 × 200) — one self-selected settled order.

  Shares the `FsHeroWidget` JS hook so selection changes replay the same
  cross-fade animation. The click subject is the order id — a flat
  string that travels fine via `phx-value-subject`; no structured subject
  is needed.

  Plan: docs/solana/realtime_widgets_plan.md · §F `fs_square_compact`
  Mock: docs/solana/widgets_mocks/fs_square_compact_mock.html
  """

  use Phoenix.Component

  import BlocksterV2Web.Widgets.WidgetShared

  alias BlocksterV2Web.Widgets.FsHeroHelpers

  attr :banner, :map, required: true
  attr :trades, :list, default: []
  attr :selection, :any, default: nil
  attr :order_override, :map, default: nil
  attr :tracker_error?, :boolean, default: false

  def fs_square_compact(assigns) do
    order = FsHeroHelpers.resolve_order(assigns.trades, assigns.selection, assigns.order_override)
    {status_label, _status_class} = FsHeroHelpers.status(order)

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:status_label, status_label)
      |> assign(:profit_pct, order && FsHeroHelpers.profit_pct(order))
      |> assign(:marker_pct, order && FsHeroHelpers.conviction_marker_pct(order))

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell relative w-[200px] h-[200px] flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="FsHeroWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_square_compact"
      data-order-id={@order && @order["id"]}
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject={@order && @order["id"]}
    >
      <%!-- Mini chrome --%>
      <div class="relative z-10 h-[34px] px-2.5 flex items-center gap-2 border-b border-white/[0.06] shrink-0">
        <span class="inline-flex items-center shrink-0" style="line-height:1;">
          <img
            class="h-[18px] w-auto block select-none"
            src="https://fateswap.io/images/logo-full.svg"
            alt="FateSwap"
          />
          <span
            class="bw-display"
            style="font-size:10px;font-weight:800;letter-spacing:0.1em;text-transform:uppercase;color:#E8E4DD;margin-left:-20px;line-height:1;"
          >
            Solana&nbsp;DEX
          </span>
        </span>
        <span class="flex-1"></span>
        <span class="bw-display inline-flex items-center gap-1 text-[9px] font-semibold tracking-[0.12em] text-[#22C55E]">
          <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>LIVE
        </span>
      </div>

      <%= if @order do %>
        <%!-- Body --%>
        <div
          class="relative z-10 px-3 pt-2.5 pb-1.5 flex-1 flex flex-col min-h-0 bw-fs-hero-fade"
          data-role="fs-hero-body"
        >
          <%!-- Row: side + token + pnl --%>
          <div class="flex items-center justify-between gap-2">
            <span class="inline-flex items-center gap-1.5 min-w-0">
              <span class={[
                "w-4 h-4 rounded inline-flex items-center justify-center text-[10px] font-bold shrink-0",
                side_chip_class(@order)
              ]}>
                {side_arrow(@order)}
              </span>
              <.token_chip order={@order} />
              <span class="bw-display text-[13px] font-bold text-[#E8E4DD] tracking-[0.02em] truncate">
                {FsHeroHelpers.token_symbol(@order)}
              </span>
            </span>
            <span class={[
              "bw-mono text-[11px] font-semibold px-1.5 py-0.5 rounded inline-flex items-center gap-0.5 leading-tight",
              pnl_class(@order)
            ]}>
              <span class="text-[8px]">{pnl_arrow(@order)}</span>
              {FsHeroHelpers.format_profit_pct(@profit_pct) |> strip_parens()}
            </span>
          </div>

          <%!-- Received --%>
          <div class="flex items-baseline justify-between gap-2 mt-2 px-2 py-1.5 rounded-md bg-[#22C55E]/[0.08]">
            <span class="bw-display text-[8px] uppercase tracking-[0.14em] font-semibold text-[#22C55E]">
              Received
            </span>
            <span class="bw-mono text-[12px] font-bold text-[#22C55E] inline-flex items-center gap-1">
              {received_primary(@order)}
              <.token_chip order={@order} variant={received_variant(@order)} size={:xs} />
            </span>
          </div>

          <%!-- Paid --%>
          <div class="flex items-baseline justify-between gap-2 mt-1.5 px-2 py-1.5 rounded-md">
            <span class="bw-display text-[8px] uppercase tracking-[0.14em] font-semibold text-[#6B7280]">
              Paid
            </span>
            <span class="bw-mono text-[12px] font-bold text-[#E8E4DD] inline-flex items-center gap-1">
              {paid_primary(@order)}
              <.token_chip order={@order} variant={paid_variant(@order)} size={:xs} />
            </span>
          </div>

          <%!-- Conviction bar --%>
          <div class="mt-auto pt-1.5">
            <div
              class="relative h-[3px] rounded-full"
              style="background:linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%);"
            >
              <div
                class="absolute top-[-3px] w-[3px] h-[9px] rounded-full bg-white"
                style={"left:#{@marker_pct || 50}%;box-shadow:0 0 0 2px rgba(255,255,255,0.12), 0 0 6px rgba(0,0,0,0.6);"}
              >
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <%= if @tracker_error? do %>
          <.tracker_error_placeholder brand={:fs} class="flex-1" />
        <% else %>
          <div class="relative z-10 px-3 pt-2.5 pb-1.5 flex-1 flex flex-col gap-2" data-role="fs-square-skeleton">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-1.5">
                <.skeleton_bar class="w-4 h-4" />
                <.skeleton_circle class="w-[18px] h-[18px]" />
                <.skeleton_bar class="w-10 h-3" />
              </div>
              <.skeleton_bar class="w-12 h-3" />
            </div>
            <.skeleton_bar class="w-full h-8" />
            <.skeleton_bar class="w-full h-8" />
            <.skeleton_bar class="w-full h-1 mt-auto" />
          </div>
        <% end %>
      <% end %>

      <%!-- Footer --%>
      <div class="relative z-10 h-[24px] px-2.5 flex items-center justify-between border-t border-white/[0.06] shrink-0">
        <span class="bw-display inline-flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-[0.14em] text-[#9CA3AF]">
          <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>Solana DEX
        </span>
        <span class="bw-display text-[10px] font-medium text-[#E8E4DD] tracking-[0.02em]">
          view →
        </span>
      </div>
    </div>
    """
  end

  # ── Side chip ─────────────────────────────────────────────────────────────

  defp side_chip_class(%{"side" => "sell"}),
    do: "bg-[#EAB308]/[0.14] text-[#EAB308]"

  defp side_chip_class(_), do: "bg-[#22C55E]/[0.12] text-[#22C55E]"

  defp side_arrow(%{"side" => "sell"}), do: "↘"
  defp side_arrow(_), do: "↗"

  # ── PnL pill ──────────────────────────────────────────────────────────────

  defp pnl_class(%{"filled" => false}),
    do: "text-[#EF4444] bg-[#EF4444]/[0.10]"

  defp pnl_class(%{"profit_ui" => v}) when is_number(v) and v < 0,
    do: "text-[#EF4444] bg-[#EF4444]/[0.10]"

  defp pnl_class(_), do: "text-[#22C55E] bg-[#22C55E]/[0.10]"

  defp pnl_arrow(%{"filled" => false}), do: "▼"

  defp pnl_arrow(%{"profit_ui" => v}) when is_number(v) and v < 0, do: "▼"
  defp pnl_arrow(_), do: "▲"

  defp strip_parens(str) when is_binary(str) do
    str |> String.replace("(", "") |> String.replace(")", "")
  end

  defp strip_parens(_), do: ""

  # ── Token chip sub-component ─────────────────────────────────────────────

  attr :order, :map, required: true
  attr :variant, :atom, default: :token
  attr :size, :atom, default: :sm

  defp token_chip(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center rounded-full shrink-0 text-white bw-display font-extrabold select-none leading-none",
        chip_size(@size)
      ]}
      style={chip_style(@variant)}
    >
      {chip_text(@variant, @order)}
    </span>
    """
  end

  defp chip_size(:xs), do: "w-3 h-3 text-[7px]"
  defp chip_size(_), do: "w-[18px] h-[18px] text-[10px]"

  defp chip_style(:sol),
    do:
      "background:#0A0A0F url('https://ik.imagekit.io/blockster/solana-sol-logo.png') center/cover no-repeat;box-shadow:0 0 0 1px rgba(153,69,255,0.25);color:transparent;"

  defp chip_style(_),
    do:
      "background:radial-gradient(circle at 30% 30%,#a78bfa,#7c3aed 60%,#4c1d95);box-shadow:0 0 0 1px rgba(167,139,250,0.25);"

  defp chip_text(:sol, _), do: "◎"
  defp chip_text(_, order), do: FsHeroHelpers.token_letter(order)

  # ── Received / Paid primary values ────────────────────────────────────────

  defp received_primary(%{"side" => "sell"} = o), do: FsHeroHelpers.format_sol(o["payout_ui"])
  defp received_primary(o), do: FsHeroHelpers.format_token_qty(o["payout_ui"])

  defp paid_primary(%{"side" => "sell"} = o), do: FsHeroHelpers.format_token_qty(o["sol_amount_ui"])
  defp paid_primary(o), do: FsHeroHelpers.format_sol(o["sol_amount_ui"])

  defp received_variant(%{"side" => "sell"}), do: :sol
  defp received_variant(_), do: :token

  defp paid_variant(%{"side" => "sell"}), do: :token
  defp paid_variant(_), do: :sol
end
