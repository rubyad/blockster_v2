defmodule BlocksterV2Web.Widgets.FsHeroLandscape do
  @moduledoc """
  FateSwap landscape hero card (full × ~480, mobile full × auto).

  Wider variant of `fs_hero_portrait`. Two-column 2×2 stat grid
  (Trader Received / Trader Paid / Profit / Fill Chance), Swap Complete
  badge, conviction bar with rainbow gradient marker, and a FATESWAP
  footer with the marketing tagline.

  Shares the `FsHeroWidget` JS hook with the portrait variant — both
  listen for `widget:<banner_id>:select`, both receive the same
  `{order_id, order}` payload, both cross-fade on change.

  Plan: docs/solana/realtime_widgets_plan.md · §F `fs_hero_landscape`
  Mock: docs/solana/widgets_mocks/fs_hero_landscape_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.FsHeroHelpers

  attr :banner, :map, required: true
  attr :trades, :list, default: []
  attr :selection, :any, default: nil
  attr :order_override, :map, default: nil

  def fs_hero_landscape(assigns) do
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
      class="bw-widget bw-shell relative w-full flex flex-col overflow-hidden cursor-pointer text-[#E8E4DD] bw-shell-bg-grid"
      style="min-height:480px;"
      phx-hook="FsHeroWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_hero_landscape"
      data-order-id={@order && @order["id"]}
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject={@order && @order["id"]}
    >
      <%!-- Header --%>
      <div class="relative z-[1] px-6 pt-4 pb-3 flex flex-wrap md:flex-nowrap items-center gap-3 md:gap-5 border-b border-white/[0.06]">
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
        <span
          class="bw-display flex-1 text-center font-extrabold text-[14px] leading-[1.15] basis-full md:basis-auto order-last md:order-none"
          style="letter-spacing:-0.005em;background:linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;"
        >
          {FsHeroHelpers.tagline()}
        </span>
        <span class="bw-display inline-flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.12em] text-[#22C55E] shrink-0">
          <span class="bw-pulse-dot" style="width:5px;height:5px;"></span>LIVE
        </span>
        <span
          :if={@order && @order["settled_at"]}
          class="bw-mono text-[10px] text-[#4B5563] shrink-0 hidden md:inline"
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
          <span class={[
            "bw-display self-start inline-flex items-center rounded-full px-3 py-1.5 text-[10px] font-bold uppercase tracking-[0.18em] leading-none mb-3",
            @status_class
          ]}>
            {@status_label}
          </span>

          <h2
            class="bw-display font-extrabold text-[32px] md:text-[42px] leading-[1.05] m-0 flex items-center gap-2.5 flex-wrap"
            style="letter-spacing:-0.02em;"
            data-role="fs-hero-heading"
          >
            {FsHeroHelpers.action_verb(@order)}
            <span class="bw-mono font-extrabold">{FsHeroHelpers.format_token_qty(@order["payout_ui"])}</span>
            <span class="inline-flex items-center gap-2 align-middle">
              <.token_icon order={@order} size={:lg} />
              {FsHeroHelpers.token_symbol(@order)}
            </span>
          </h2>

          <p class="text-[15px] text-[#9CA3AF] mt-2 font-medium">
            at <span class="bw-mono text-[#E8E4DD] font-bold">{FsHeroHelpers.format_percent(@order["discount_pct"])}</span>
            {FsHeroHelpers.discount_kind(@order)}
          </p>

          <%!-- 2×2 stat grid --%>
          <div class="grid grid-cols-2 gap-2.5 mt-5">
            <.fs_cell
              label="Trader Received"
              value_text={received_primary(@order)}
              ticker={received_ticker(@order)}
              variant={received_variant(@order)}
              usd={FsHeroHelpers.format_usd(@order["payout_usd"])}
              color_class="text-[#22C55E]"
              bg_class="bg-[#22C55E]/[0.08] border-[#22C55E]/[0.18]"
              label_color="text-[#22C55E]"
              order={@order}
            />
            <.fs_cell
              label={FsHeroHelpers.paid_label(@order)}
              value_text={paid_primary(@order)}
              ticker={paid_ticker(@order)}
              variant={paid_variant(@order)}
              usd={FsHeroHelpers.format_usd(@order["sol_usd"])}
              color_class="text-[#E8E4DD]"
              bg_class="bg-white/[0.03] border-white/[0.06]"
              label_color="text-[#6B7280]"
              order={@order}
            />
            <.fs_cell
              label="Profit"
              value_text={FsHeroHelpers.format_profit_with_sign(@order["profit_ui"])}
              ticker={profit_ticker(@order)}
              variant={profit_variant(@order)}
              usd={FsHeroHelpers.format_usd(@order["profit_usd"])}
              color_class={FsHeroHelpers.profit_color(@order)}
              bg_class="bg-white/[0.03] border-white/[0.06]"
              label_color="text-[#6B7280]"
              pct={FsHeroHelpers.format_profit_pct(FsHeroHelpers.profit_pct(@order))}
              order={@order}
            />
            <div class="flex flex-col gap-1 px-4 py-3.5 rounded-[10px] border bg-white/[0.03] border-white/[0.06]">
              <span class="bw-display text-[10px] uppercase tracking-[0.18em] font-semibold text-[#6B7280]">
                Fill Chance
              </span>
              <span class="bw-mono text-[20px] font-bold text-[#E8E4DD] inline-flex items-baseline gap-1 leading-tight">
                {fill_chance_text(@order)}<span class="text-[14px] font-semibold">%</span>
              </span>
              <span class="bw-mono text-[12px] text-[#6B7280]">
                roll &lt; threshold
              </span>
            </div>
          </div>

          <%!-- Swap Complete badge --%>
          <div
            :if={@order["filled"] == true}
            class="mt-3.5 py-2.5 px-4 flex items-center justify-center gap-2.5 rounded-[10px] bg-[#22C55E]/[0.06] border border-[#22C55E]/[0.16]"
          >
            <svg class="w-[16px] h-[16px] text-[#22C55E] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10" />
              <polyline points="8.5 12 11 14.5 16 9.5" />
            </svg>
            <span class="bw-display text-[13px] font-semibold text-[#22C55E]">
              Swap complete
            </span>
          </div>

          <%!-- Conviction bar --%>
          <div class="mt-4">
            <div class="flex items-center justify-between gap-3 mb-1.5">
              <span class="bw-display text-[10px] uppercase tracking-[0.18em] font-semibold text-[#6B7280]">
                Conviction:<strong class="text-[#E8E4DD] font-bold ml-1">{FsHeroHelpers.conviction_label(@order)}</strong>
              </span>
              <span class="bw-mono text-[11px] text-[#9CA3AF]">
                {conviction_caption(@order)}
              </span>
            </div>
            <div
              class="relative h-1 rounded-full overflow-hidden"
              style="background:linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%);"
            >
              <div
                class="absolute top-[-3px] w-[3px] h-[10px] bg-white rounded-full"
                style={"left:#{FsHeroHelpers.conviction_marker_pct(@order)}%;box-shadow:0 0 0 2px rgba(255,255,255,0.12),0 0 8px rgba(0,0,0,0.6);"}
              />
            </div>
          </div>

          <%!-- Quote --%>
          <p class="bw-display italic text-[12px] text-[#6B7280] mt-4 text-center leading-relaxed">
            "{FsHeroHelpers.quote_text(@order)}"
          </p>
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

      <%!-- Footer --%>
      <div class="relative z-[1] px-6 py-3.5 flex items-center justify-between gap-4 border-t border-white/[0.06]">
        <span class="bw-display text-[13px] font-medium text-[#9CA3AF] leading-snug">
          Memecoin trading on steroids.
        </span>
        <span :if={FsHeroHelpers.tx_label(@order || %{}) != ""} class="bw-mono text-[11px]">
          <span class="text-[#6B7280] font-medium">TX:</span>
          <span class="text-[#E8E4DD] font-semibold ml-1">
            {FsHeroHelpers.tx_label(@order || %{})}
          </span>
        </span>
        <span :if={FsHeroHelpers.tx_label(@order || %{}) == ""} class="bw-display text-[12px] font-semibold text-[#E8E4DD] whitespace-nowrap">
          Open FateSwap →
        </span>
      </div>
    </div>
    """
  end

  # ── Token icon sub-component ──────────────────────────────────────────────

  attr :order, :map, required: true
  attr :size, :atom, default: :sm
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

  defp token_icon_size(:lg), do: "w-[32px] h-[32px] text-[15px]"
  defp token_icon_size(_), do: "w-[20px] h-[20px] text-[10px]"

  defp token_icon_style(:sol),
    do:
      "background:#0A0A0F url('https://ik.imagekit.io/blockster/solana-sol-logo.png') center/cover no-repeat;box-shadow:0 0 0 1.5px rgba(153,69,255,0.28),0 2px 4px rgba(0,0,0,0.3);color:transparent;"

  defp token_icon_style(_),
    do:
      "background:radial-gradient(circle at 30% 30%,#a78bfa,#7c3aed 60%,#4c1d95);box-shadow:0 0 0 1.5px rgba(167,139,250,0.25),0 2px 4px rgba(0,0,0,0.3);"

  defp token_icon_text(:sol, _), do: "◎"
  defp token_icon_text(_, order), do: FsHeroHelpers.token_letter(order)

  # ── Cell sub-component ────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value_text, :string, required: true
  attr :ticker, :string, required: true
  attr :variant, :atom, default: :token
  attr :usd, :string, default: ""
  attr :color_class, :string, default: "text-[#E8E4DD]"
  attr :bg_class, :string, default: "bg-white/[0.03] border-white/[0.06]"
  attr :label_color, :string, default: "text-[#6B7280]"
  attr :pct, :string, default: ""
  attr :order, :map, required: true

  defp fs_cell(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1 px-4 py-3.5 rounded-[10px] border", @bg_class]}>
      <span class={[
        "bw-display text-[10px] uppercase tracking-[0.18em] font-semibold",
        @label_color
      ]}>
        {@label}
      </span>
      <span class={[
        "bw-mono text-[18px] md:text-[20px] font-bold inline-flex items-center gap-1.5 leading-tight flex-wrap",
        @color_class
      ]}>
        {@value_text}
        <.token_icon order={@order} size={:sm} variant={@variant} />
        <span class="text-[13px] md:text-[14px] font-semibold tracking-[0.03em]">
          {@ticker}
        </span>
        <span :if={@pct != ""} class="bw-mono text-[12px] md:text-[13px] font-medium text-[#4ade80] ml-0.5">
          {@pct}
        </span>
      </span>
      <span :if={@usd != ""} class="bw-mono text-[11px] md:text-[12px] text-[#6B7280]">
        {@usd}
      </span>
    </div>
    """
  end

  # ── Per-side value helpers (shared shape w/ portrait) ─────────────────────

  defp received_primary(%{"side" => "sell"} = o), do: FsHeroHelpers.format_sol(o["payout_ui"])
  defp received_primary(o), do: FsHeroHelpers.format_token_qty(o["payout_ui"])

  defp received_ticker(%{"side" => "sell"}), do: "SOL"
  defp received_ticker(o), do: FsHeroHelpers.token_symbol(o)

  defp received_variant(%{"side" => "sell"}), do: :sol
  defp received_variant(_), do: :token

  defp paid_primary(%{"side" => "sell"} = o),
    do: FsHeroHelpers.format_token_qty(o["sol_amount_ui"])

  defp paid_primary(o), do: FsHeroHelpers.format_sol(o["sol_amount_ui"])

  defp paid_ticker(%{"side" => "sell"} = o), do: FsHeroHelpers.token_symbol(o)
  defp paid_ticker(_), do: "SOL"

  defp paid_variant(%{"side" => "sell"}), do: :token
  defp paid_variant(_), do: :sol

  defp profit_ticker(%{"side" => "sell"}), do: "SOL"
  defp profit_ticker(o), do: FsHeroHelpers.token_symbol(o)

  defp profit_variant(%{"side" => "sell"}), do: :sol
  defp profit_variant(_), do: :token

  defp fill_chance_text(order) do
    case FsHeroHelpers.fill_chance(order) do
      p when is_number(p) -> :io_lib.format("~.2f", [p * 1.0]) |> IO.iodata_to_binary()
      _ -> "—"
    end
  end

  defp conviction_caption(order) do
    pct =
      case order["discount_pct"] do
        v when is_number(v) -> FsHeroHelpers.format_percent(v)
        _ -> "—"
      end

    zone =
      cond do
        is_number(FsHeroHelpers.fill_chance(order)) and FsHeroHelpers.fill_chance(order) >= 70 ->
          "low-risk zone"

        is_number(FsHeroHelpers.fill_chance(order)) and FsHeroHelpers.fill_chance(order) >= 40 ->
          "mid-risk zone"

        true ->
          "high-risk zone"
      end

    "#{pct} #{FsHeroHelpers.discount_kind(order)} · #{zone}"
  end
end
