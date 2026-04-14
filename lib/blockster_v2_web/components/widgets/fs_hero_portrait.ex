defmodule BlocksterV2Web.Widgets.FsHeroPortrait do
  @moduledoc """
  FateSwap portrait hero card (440 × ~720, mobile full × ~640).

  Self-selects one recent settled order via `WidgetSelector` and
  presents it as a share-card-style overlay:

    * status pill ("ORDER FILLED" / "DISCOUNT FILLED" / "NOT FILLED")
    * "Bought X TOKEN at Y% discount" headline (third-person copy —
      "Trader Received / Trader Paid", not "You")
    * stacked Trader Received + Trader Paid boxes
    * Profit row
    * Fill chance + TX hash footer

  Wrapped by the shared `FsHeroWidget` JS hook which cross-fades on
  `widget:<banner_id>:select` events. The click subject is the order
  id; the `WidgetEvents` macro + `ClickRouter` handle the redirect to
  `fateswap.io/orders/:id`.

  Plan: docs/solana/realtime_widgets_plan.md · §F `fs_hero_portrait`
  Mock: docs/solana/widgets_mocks/fs_hero_portrait_mock.html
  Locked-in decisions honored: third-person copy; Solana DEX label
  + brand-gradient tagline; Swap Complete checkmark on filled orders;
  Fill chance + TX hash footer (no Roll number).
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.FsHeroHelpers

  attr :banner, :map, required: true
  attr :trades, :list, default: []
  attr :selection, :any, default: nil
  attr :order_override, :map, default: nil

  def fs_hero_portrait(assigns) do
    order = FsHeroHelpers.resolve_order(assigns.trades, assigns.selection, assigns.order_override)
    {status_label, status_class} = FsHeroHelpers.status(order)

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:status_label, status_label)
      |> assign(:status_class, status_class)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell relative w-full md:w-[440px] max-w-[440px] mx-auto flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD] bw-shell-bg-grid"
      style="min-height:640px;"
      phx-hook="FsHeroWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_hero_portrait"
      data-order-id={@order && @order["id"]}
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject={@order && @order["id"]}
    >
      <%!-- Header --%>
      <div class="relative z-[1] px-5 pt-4 pb-3 flex items-center gap-3 border-b border-white/[0.06]">
        <span class="inline-flex items-center shrink-0">
          <img
            class="h-[22px] w-auto block select-none"
            src="https://fateswap.io/images/logo-full.svg"
            alt="FateSwap"
          />
          <span
            class="bw-display font-extrabold uppercase"
            style="font-size:13px;letter-spacing:0.14em;color:#E8E4DD;line-height:1;margin-left:-24px;"
          >
            Solana&nbsp;DEX
          </span>
        </span>
        <span class="flex-1"></span>
        <span class="bw-display inline-flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.12em] text-[#22C55E]">
          <span class="bw-pulse-dot" style="width:5px;height:5px;"></span>LIVE
        </span>
        <span
          :if={@order && @order["settled_at"]}
          class="bw-mono text-[10px] text-[#4B5563]"
          data-role="fs-hero-time"
        >
          {FsHeroHelpers.relative_time(@order["settled_at"])}
        </span>
      </div>

      <%= if @order do %>
        <div
          class="relative z-[1] px-6 py-5 flex-1 flex flex-col bw-fs-hero-fade"
          data-role="fs-hero-body"
        >
          <%!-- Gradient tagline --%>
          <h1
            class="bw-display text-center font-extrabold text-[20px] leading-[1.15] mb-5"
            style="letter-spacing:-0.01em;background:linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;"
          >
            {FsHeroHelpers.tagline()}
          </h1>

          <%!-- Status pill --%>
          <div class="flex justify-center mb-4">
            <span class={[
              "bw-display inline-flex items-center rounded-full px-4 py-1.5 text-[11px] font-bold uppercase tracking-[0.18em] leading-none",
              @status_class
            ]}>
              {@status_label}
            </span>
          </div>

          <%!-- Headline --%>
          <h2
            class="bw-display text-center font-extrabold text-[28px] md:text-[30px] leading-[1.1] m-0 flex justify-center items-center gap-2 flex-wrap"
            style="letter-spacing:-0.02em;"
            data-role="fs-hero-heading"
          >
            {FsHeroHelpers.action_verb(@order)}
            <span class="bw-mono font-extrabold">{FsHeroHelpers.format_token_qty(@order["payout_ui"])}</span>
            <span class="inline-flex items-center gap-1.5 align-middle">
              <.token_icon order={@order} size={:md} />
              {FsHeroHelpers.token_symbol(@order)}
            </span>
          </h2>

          <p class="text-center text-[14px] text-[#9CA3AF] mt-1.5 font-medium">
            at <span class="bw-mono text-[#E8E4DD] font-bold">{FsHeroHelpers.format_percent(@order["discount_pct"])}</span>
            {FsHeroHelpers.discount_kind(@order)}
          </p>

          <%!-- Received / Paid boxes --%>
          <div class="flex flex-col gap-2.5 mt-5" data-role="fs-hero-boxes">
            <div class="flex items-center justify-between gap-3 px-4 py-3 rounded-[10px] border bg-[#22C55E]/[0.08] border-[#22C55E]/[0.18]">
              <span class="bw-display text-[10px] uppercase tracking-[0.18em] font-semibold text-[#22C55E]">
                Trader Received
              </span>
              <div class="flex flex-col items-end gap-0.5">
                <span class="bw-mono text-[17px] font-bold text-[#22C55E] inline-flex items-center gap-1.5 leading-tight">
                  {received_primary(@order)}
                  <.token_icon order={@order} size={:sm} variant={received_variant(@order)} />
                  <span class="text-[12px] font-semibold tracking-[0.03em]">
                    {received_ticker(@order)}
                  </span>
                </span>
                <span class="bw-mono text-[11px] text-[#6B7280]">
                  {FsHeroHelpers.format_usd(@order["payout_usd"] || @order["profit_usd"])}
                </span>
              </div>
            </div>

            <div class="flex items-center justify-between gap-3 px-4 py-3 rounded-[10px] border bg-white/[0.03] border-white/[0.06]">
              <span class="bw-display text-[10px] uppercase tracking-[0.18em] font-semibold text-[#6B7280]">
                {FsHeroHelpers.paid_label(@order)}
              </span>
              <div class="flex flex-col items-end gap-0.5">
                <span class="bw-mono text-[17px] font-bold text-[#E8E4DD] inline-flex items-center gap-1.5 leading-tight">
                  {paid_primary(@order)}
                  <.token_icon order={@order} size={:sm} variant={paid_variant(@order)} />
                  <span class="text-[12px] font-semibold tracking-[0.03em]">
                    {paid_ticker(@order)}
                  </span>
                </span>
                <span class="bw-mono text-[11px] text-[#6B7280]">
                  {FsHeroHelpers.format_usd(@order["sol_usd"])}
                </span>
              </div>
            </div>
          </div>

          <%!-- Profit row --%>
          <div class="flex items-center justify-between gap-3 mt-4 pt-3.5 px-1 border-t border-white/[0.06]">
            <span class="bw-display text-[11px] uppercase tracking-[0.18em] font-semibold text-[#6B7280]">
              Profit
            </span>
            <div class="flex flex-col items-end gap-0.5">
              <span class={[
                "bw-mono text-[16px] font-bold inline-flex items-center gap-1.5 leading-tight",
                FsHeroHelpers.profit_color(@order)
              ]}>
                {FsHeroHelpers.format_profit_with_sign(@order["profit_ui"])}
                <.token_icon order={@order} size={:sm} variant={profit_variant(@order)} />
                {profit_ticker(@order)}
                <span class="bw-mono text-[12px] font-medium text-[#4ade80] ml-1">
                  {FsHeroHelpers.format_profit_pct(FsHeroHelpers.profit_pct(@order))}
                </span>
              </span>
              <span class="bw-mono text-[11px] text-[#6B7280]">
                {FsHeroHelpers.format_usd(@order["profit_usd"])}
              </span>
            </div>
          </div>

          <%!-- Swap complete badge (filled only) --%>
          <div
            :if={@order["filled"] == true}
            class="mt-4 py-3 px-4 flex items-center justify-center gap-2.5 rounded-[10px] bg-[#22C55E]/[0.06] border border-[#22C55E]/[0.16]"
          >
            <svg class="w-[18px] h-[18px] text-[#22C55E] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10" />
              <polyline points="8.5 12 11 14.5 16 9.5" />
            </svg>
            <span class="bw-display text-[14px] font-semibold text-[#22C55E]">
              Swap complete
            </span>
          </div>

          <%!-- Meta footer --%>
          <div class="mt-auto pt-4 flex items-center justify-between text-[11px] text-[#4B5563] bw-mono">
            <span>
              <span class="text-[#6B7280] font-medium">Fill chance:</span>
              <span class="text-[#E8E4DD] font-semibold ml-1">
                {FsHeroHelpers.format_percent(FsHeroHelpers.fill_chance(@order))}
              </span>
            </span>
            <span :if={FsHeroHelpers.tx_label(@order) != ""}>
              <span class="text-[#6B7280] font-medium">TX:</span>
              <span class="text-[#E8E4DD] font-semibold ml-1">
                {FsHeroHelpers.tx_label(@order)}
              </span>
            </span>
          </div>
        </div>
      <% else %>
        <div class="relative z-[1] flex-1 flex items-center justify-center px-6 py-12 text-center">
          <div>
            <div class="bw-display text-[10px] uppercase tracking-[0.18em] text-[#6B7280] mb-1">
              Waiting for a standout order
            </div>
            <div class="bw-display text-[11px] text-[#4B5563]">
              The self-selected hero populates once FateSwap settles its next trade.
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Token icon sub-component ──────────────────────────────────────────────

  attr :order, :map, required: true
  attr :size, :atom, default: :md
  attr :variant, :atom, default: :token

  defp token_icon(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center rounded-full shrink-0 text-white bw-display font-extrabold select-none",
        token_icon_size(@size)
      ]}
      style={token_icon_style(@variant)}
    >
      {token_icon_text(@variant, @order)}
    </span>
    """
  end

  defp token_icon_size(:md), do: "w-[22px] h-[22px] text-[11px]"
  defp token_icon_size(_), do: "w-[18px] h-[18px] text-[9px]"

  defp token_icon_style(:sol),
    do:
      "background:#0A0A0F url('https://ik.imagekit.io/blockster/solana-sol-logo.png') center/cover no-repeat;box-shadow:0 0 0 1.5px rgba(153,69,255,0.28),0 2px 4px rgba(0,0,0,0.3);color:transparent;"

  defp token_icon_style(_),
    do:
      "background:radial-gradient(circle at 30% 30%,#a78bfa,#7c3aed 60%,#4c1d95);box-shadow:0 0 0 1.5px rgba(167,139,250,0.25),0 2px 4px rgba(0,0,0,0.3);"

  defp token_icon_text(:sol, _), do: "◎"
  defp token_icon_text(_, order), do: FsHeroHelpers.token_letter(order)

  # ── Per-side value helpers ────────────────────────────────────────────────

  # For buy: received = token qty; paid = SOL.
  # For sell: received = SOL; paid = token qty.
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

  defp profit_ticker(%{"side" => "sell"}), do: "SOL"
  defp profit_ticker(o), do: FsHeroHelpers.token_symbol(o)

  defp profit_variant(%{"side" => "sell"}), do: :sol
  defp profit_variant(_), do: :token
end
