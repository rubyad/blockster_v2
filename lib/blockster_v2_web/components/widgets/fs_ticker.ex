defmodule BlocksterV2Web.Widgets.FsTicker do
  @moduledoc """
  FateSwap full-width horizontal ticker (full × 56, mobile full × 48).

  CSS-only marquee of the last 20 settled trades. Brand + LIVE pill on
  the left, marquee track in the middle (duplicated item set for a
  seamless loop), "Open FateSwap" CTA on the right. Each item: side
  arrow (↗ buy / ↘ sell), token logo + symbol, amount, profit/loss
  pill. Hover pauses the scroll.

  All-data widget: whole div `phx-click="widget_click"` with
  `subject="fs"` routes to the FateSwap homepage via `ClickRouter`.

  Plan: docs/solana/realtime_widgets_plan.md · §F `fs_ticker`
  Mock: docs/solana/widgets_mocks/fs_ticker_mock.html
  """

  use Phoenix.Component

  import BlocksterV2Web.Widgets.WidgetShared

  @max_items 20

  attr :banner, :map, required: true
  attr :trades, :list, default: []
  attr :tracker_error?, :boolean, default: false

  def fs_ticker(assigns) do
    trades = Enum.take(assigns.trades || [], @max_items)

    assigns = assign(assigns, :trades, trades)

    ~H"""
    <div
      id={"widget-#{@banner.id}"}
      class="bw-widget bw-shell bw-ticker relative w-full h-[56px] flex items-stretch overflow-hidden cursor-pointer text-[#E8E4DD]"
      phx-hook="FsTickerWidget"
      data-banner-id={@banner.id}
      data-widget-type="fs_ticker"
      phx-click="widget_click"
      phx-value-banner_id={@banner.id}
      phx-value-subject="fs"
    >
      <%!-- Brand lock-up --%>
      <div class="relative z-[2] shrink-0 flex items-center gap-[10px] pl-[18px] pr-4 border-r border-white/[0.06] bg-[#0A0A0F]">
        <span class="relative inline-flex items-center" style="line-height:1;">
          <img
            class="h-[22px] w-auto block select-none"
            src="https://fateswap.io/images/logo-full.svg"
            alt="FateSwap"
          />
          <span
            class="bw-display font-extrabold uppercase"
            style="font-size:12px;letter-spacing:0.12em;color:#E8E4DD;line-height:1;margin-left:-24px;"
          >
            Solana&nbsp;DEX
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
      <div class="bw-marquee" data-role="fs-ticker-marquee">
        <%= cond do %>
          <% @trades == [] and @tracker_error? -> %>
            <div class="flex items-center h-full px-4 gap-2">
              <span class="bw-err-dot"></span>
              <span class="bw-display text-[10px] uppercase tracking-[0.14em] text-[#EAB308]">
                FateSwap feed paused — retrying
              </span>
            </div>
          <% @trades == [] -> %>
            <div class="flex items-center h-full px-4 gap-3" data-role="fs-ticker-skeleton">
              <div :for={_ <- 1..8} class="flex items-center gap-1.5">
                <.skeleton_circle class="w-3 h-3" />
                <.skeleton_bar class="w-14 h-3" />
                <.skeleton_bar class="w-10 h-2.5" />
              </div>
            </div>
          <% true -> %>
          <div class="bw-marquee-track bw-marquee-track--slow" data-role="fs-ticker-track">
            <.fs_ticker_items trades={@trades} />
            <.fs_ticker_items trades={@trades} />
          </div>
        <% end %>
      </div>

      <%!-- Right CTA --%>
      <div class="relative z-[2] shrink-0 hidden md:flex items-center px-[18px] border-l border-white/[0.06] bg-[#0A0A0F]">
        <span class="bw-display text-[11px] font-semibold tracking-[0.02em] text-[#E8E4DD] whitespace-nowrap">
          Open FateSwap →
        </span>
      </div>
    </div>
    """
  end

  attr :trades, :list, required: true

  defp fs_ticker_items(assigns) do
    ~H"""
    <div
      :for={trade <- @trades}
      class="inline-flex items-center gap-[10px] px-[18px] h-full border-r border-white/[0.06] whitespace-nowrap transition-colors duration-150 hover:bg-white/[0.02]"
      data-role="fs-ticker-item"
      data-trade-id={trade["id"]}
    >
      <span class={[
        "w-[18px] h-[18px] rounded flex items-center justify-center text-[10px] font-bold shrink-0",
        side_class(trade)
      ]}>
        {side_arrow(trade)}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <img
          :if={trade["token_logo_url"]}
          src={trade["token_logo_url"]}
          alt={trade["token_symbol"] || ""}
          class="w-[18px] h-[18px] rounded-full bg-[#1f1f28] object-cover block shrink-0"
          onerror="this.style.display='none'"
        />
        <span class="bw-display font-bold text-[11px] text-[#E8E4DD] tracking-[0.04em]">
          {token_symbol(trade)}
        </span>
      </span>
      <span class="bw-mono text-[11px] font-medium text-[#9CA3AF] hidden md:inline">
        {format_amount(trade)}
      </span>
      <span class={[
        "bw-mono text-[11px] font-semibold rounded-[3px] inline-flex items-center gap-0.5 px-1.5 py-[2px] leading-none",
        pnl_pill_class(trade)
      ]}>
        <span class="text-[9px] leading-none -translate-y-[0.5px]">{pnl_arrow(trade)}</span>{format_pnl(trade)}
      </span>
    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp side_class(%{"side" => "sell"}),
    do: "bg-[#EAB308]/12 text-[#EAB308]"

  defp side_class(_), do: "bg-[#22C55E]/12 text-[#22C55E]"

  defp side_arrow(%{"side" => "sell"}), do: "↘"
  defp side_arrow(_), do: "↗"

  defp token_symbol(trade), do: trade["token_symbol"] || "TOKEN"

  defp format_amount(%{"payout_ui" => v}) when is_number(v) do
    format_num(v)
  end

  defp format_amount(%{"sol_amount_ui" => v}) when is_number(v) do
    format_num(v)
  end

  defp format_amount(_), do: "—"

  defp format_num(v) when is_number(v) do
    cond do
      abs(v) >= 1000 ->
        :io_lib.format("~.0f", [v * 1.0]) |> IO.iodata_to_binary()

      abs(v) >= 1 ->
        :io_lib.format("~.2f", [v * 1.0]) |> IO.iodata_to_binary()

      true ->
        :io_lib.format("~.4f", [v * 1.0]) |> IO.iodata_to_binary()
    end
  end

  defp format_num(_), do: "—"

  defp pnl_pill_class(trade) do
    case pnl_direction(trade) do
      :up -> "text-[#22C55E] bg-[#22C55E]/10"
      :down -> "text-[#EF4444] bg-[#EF4444]/10"
      _ -> "text-[#6B7280] bg-white/[0.04]"
    end
  end

  defp pnl_arrow(trade) do
    case pnl_direction(trade) do
      :up -> "▲"
      :down -> "▼"
      _ -> "·"
    end
  end

  defp pnl_direction(%{"filled" => false}), do: :down

  defp pnl_direction(%{"profit_ui" => v}) when is_number(v) do
    cond do
      v > 0 -> :up
      v < 0 -> :down
      true -> :flat
    end
  end

  defp pnl_direction(%{"filled" => true}), do: :up
  defp pnl_direction(_), do: :flat

  defp format_pnl(%{"filled" => false}) do
    "NOT FILLED"
  end

  defp format_pnl(%{"multiplier" => m}) when is_number(m) do
    pct = (m - 1.0) * 100
    sign = if pct >= 0, do: "+", else: "−"
    mag = :io_lib.format("~.1f", [abs(pct) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}#{mag}%"
  end

  defp format_pnl(%{"discount_pct" => pct}) when is_number(pct) do
    sign = if pct >= 0, do: "+", else: "−"
    mag = :io_lib.format("~.1f", [abs(pct) * 1.0]) |> IO.iodata_to_binary()
    "#{sign}#{mag}%"
  end

  defp format_pnl(_), do: "—"
end
