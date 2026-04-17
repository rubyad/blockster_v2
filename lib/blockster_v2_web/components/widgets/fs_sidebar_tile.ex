defmodule BlocksterV2Web.Widgets.FsSidebarTile do
  @moduledoc """
  FateSwap sidebar tile (200 × 320) — taller sibling of `fs_square_compact`
  sized to match the height of Blockster's article-page discover-card
  sidebar boxes. Adds headline, timestamp, Received/Paid boxes, profit
  row, and conviction bar.

  Shares the `FsHeroWidget` JS hook so selection changes replay the
  cross-fade animation.

  Plan: docs/solana/realtime_widgets_plan.md · §F `fs_sidebar_tile`
  Mock: docs/solana/widgets_mocks/fs_sidebar_tile_mock.html
  """

  use Phoenix.Component

  import BlocksterV2Web.Widgets.WidgetShared

  alias BlocksterV2Web.Widgets.FsHeroHelpers

  attr :banner, :map, required: true
  attr :trades, :list, default: []
  attr :selection, :any, default: nil
  attr :order_override, :map, default: nil
  attr :tracker_error?, :boolean, default: false

  def fs_sidebar_tile(assigns) do
    order = FsHeroHelpers.resolve_order(assigns.trades, assigns.selection, assigns.order_override)
    {status_label, status_class} = FsHeroHelpers.status(order)

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:status_label, status_label)
      |> assign(:status_class, status_class)
      |> assign(:profit_pct, order && FsHeroHelpers.profit_pct(order))
      |> assign(:marker_pct, order && FsHeroHelpers.conviction_marker_pct(order))

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell relative w-[200px] h-[320px] flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="FsHeroWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_sidebar_tile"
      data-order-id={@order && @order["id"]}
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject={@order && @order["id"]}
    >
      <%!-- Two-row chrome --%>
      <div class="relative z-10 px-2.5 pt-2 pb-2 flex flex-col gap-1.5 border-b border-white/[0.06] shrink-0">
        <div class="flex items-center gap-2">
          <span class="inline-flex items-center shrink-0">
            <img
              class="h-[16px] w-auto block select-none"
              src="https://fateswap.io/images/logo-full.svg"
              alt="FateSwap"
            />
          </span>
          <span class="flex-1"></span>
          <span class="bw-display inline-flex items-center gap-1 text-[9px] font-semibold tracking-[0.12em] text-[#22C55E]">
            <span class="bw-pulse-dot" style="width:4px;height:4px;"></span>LIVE
          </span>
        </div>
        <div>
          <span
            class="bw-display"
            style="font-size:11px;font-weight:800;letter-spacing:0.16em;text-transform:uppercase;color:#E8E4DD;line-height:1;"
          >
            Solana DEX
          </span>
        </div>
      </div>

      <%= if @order do %>
        <%!-- Body --%>
        <div
          class="relative z-10 px-3 pt-2.5 pb-2 flex-1 flex flex-col min-h-0 bw-fs-hero-fade"
          data-role="fs-hero-body"
        >
          <span class={[
            "bw-display self-start inline-flex items-center px-2.5 py-[3px] rounded-full text-[9px] font-bold uppercase tracking-[0.16em] leading-none",
            @status_class
          ]}>
            {@status_label}
          </span>

          <%!-- Headline --%>
          <h2
            class="bw-display text-[15px] font-extrabold leading-[1.15] mt-2 mb-0.5 flex items-center gap-1.5 flex-wrap"
            style="letter-spacing:-0.01em;"
            data-role="fs-hero-heading"
          >
            {FsHeroHelpers.action_verb(@order)}
            <span class="bw-mono font-extrabold">
              {FsHeroHelpers.format_token_qty(@order["payout_ui"])}
            </span>
            <.token_chip order={@order} />
            <span>{FsHeroHelpers.token_symbol(@order)}</span>
          </h2>

          <p class="text-[11px] text-[#9CA3AF] font-medium mb-0.5">
            at <span class="bw-mono text-[#E8E4DD] font-bold">{FsHeroHelpers.format_percent(@order["discount_pct"])}</span>
            {FsHeroHelpers.discount_kind(@order)}
          </p>
          <p :if={@order["settled_at"]} class="bw-mono text-[9px] text-[#6B7280] mt-0.5">
            {FsHeroHelpers.relative_time(@order["settled_at"])}
          </p>

          <%!-- Received / Paid boxes --%>
          <div class="flex flex-col gap-1.5 mt-2.5">
            <div class="flex items-center justify-between gap-1.5 px-2 py-1.5 rounded-md border bg-[#22C55E]/[0.08] border-[#22C55E]/[0.18]">
              <span class="bw-display text-[8px] uppercase tracking-[0.14em] font-semibold text-[#22C55E]">
                Received
              </span>
              <span class="bw-mono text-[11px] font-bold text-[#22C55E] inline-flex items-center gap-1 leading-tight">
                {received_primary(@order)}
                <.token_chip order={@order} variant={received_variant(@order)} size={:xs} />
                <span class="text-[9px] font-semibold text-[#22C55E]/90">
                  {received_ticker(@order)}
                </span>
              </span>
            </div>
            <div class="flex items-center justify-between gap-1.5 px-2 py-1.5 rounded-md border bg-white/[0.03] border-white/[0.06]">
              <span class="bw-display text-[8px] uppercase tracking-[0.14em] font-semibold text-[#6B7280]">
                {FsHeroHelpers.paid_label(@order)}
              </span>
              <span class="bw-mono text-[11px] font-bold text-[#E8E4DD] inline-flex items-center gap-1 leading-tight">
                {paid_primary(@order)}
                <.token_chip order={@order} variant={paid_variant(@order)} size={:xs} />
                <span class="text-[9px] font-semibold text-[#9CA3AF]">
                  {paid_ticker(@order)}
                </span>
              </span>
            </div>
          </div>

          <%!-- Profit line --%>
          <div class="flex items-center justify-between gap-2 mt-2 pt-2 border-t border-white/[0.06]">
            <span class="bw-display text-[9px] uppercase tracking-[0.14em] font-semibold text-[#6B7280]">
              Profit
            </span>
            <span class={[
              "bw-mono text-[11px] font-bold inline-flex items-center leading-tight",
              FsHeroHelpers.profit_color(@order)
            ]}>
              {FsHeroHelpers.format_usd(@order["profit_usd"]) |> format_profit_usd(@order)}
              <span class="font-medium text-[9px] opacity-90 ml-1">
                {FsHeroHelpers.format_profit_pct(@profit_pct)}
              </span>
            </span>
          </div>

          <%!-- Conviction bar --%>
          <div class="mt-auto pt-2">
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
          <div class="relative z-10 px-3 pt-2.5 pb-2 flex-1 flex flex-col gap-2" data-role="fs-sidebar-skeleton">
            <.skeleton_bar class="w-24 h-4" />
            <.skeleton_bar class="w-full h-5 mt-1" />
            <.skeleton_bar class="w-3/4 h-3" />
            <.skeleton_bar class="w-full h-8 mt-2" />
            <.skeleton_bar class="w-full h-8" />
            <.skeleton_bar class="w-full h-3 mt-2" />
            <.skeleton_bar class="w-full h-1 mt-auto" />
          </div>
        <% end %>
      <% end %>

      <%!-- Footer --%>
      <div class="relative z-10 h-[28px] px-2.5 flex items-center justify-between border-t border-white/[0.06] shrink-0">
        <span class="bw-display inline-flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-[0.08em] text-[#9CA3AF] leading-tight">
          <span class="bw-pulse-dot shrink-0" style="width:4px;height:4px;"></span>
          Gamble for better prices
        </span>
      </div>
    </div>
    """
  end

  # ── Token chip ────────────────────────────────────────────────────────────

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

  # ── Received / Paid helpers ──────────────────────────────────────────────

  defp received_primary(%{"side" => "sell"} = o), do: FsHeroHelpers.format_sol(o["payout_ui"])
  defp received_primary(o), do: FsHeroHelpers.format_token_qty(o["payout_ui"])

  defp received_ticker(%{"side" => "sell"}), do: "SOL"
  defp received_ticker(o), do: FsHeroHelpers.token_symbol(o)

  defp received_variant(%{"side" => "sell"}), do: :sol
  defp received_variant(_), do: :token

  defp paid_primary(%{"side" => "sell"} = o), do: FsHeroHelpers.format_token_qty(o["sol_amount_ui"])
  defp paid_primary(o), do: FsHeroHelpers.format_sol(o["sol_amount_ui"])

  defp paid_ticker(%{"side" => "sell"} = o), do: FsHeroHelpers.token_symbol(o)
  defp paid_ticker(_), do: "SOL"

  defp paid_variant(%{"side" => "sell"}), do: :token
  defp paid_variant(_), do: :sol

  # ── Profit USD sign ──────────────────────────────────────────────────────

  # The helper returns "≈ $X.XX" (unsigned). We want "+$X.XX" / "−$X.XX".
  defp format_profit_usd(_usd_str, %{"profit_usd" => v}) when is_number(v) do
    sign = if v >= 0, do: "+", else: "−"
    mag = :io_lib.format("~.2f", [abs(v) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}$#{mag}"
  end

  defp format_profit_usd(usd_str, _), do: usd_str || ""
end
