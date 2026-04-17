defmodule BlocksterV2Web.Widgets.CfInlineLandscape do
  @moduledoc """
  Coin Flip landscape live widget (full-width × ~360) — two-column layout
  showing real settled game results. Cycles through last 10 SOL games
  via CfLiveCycle JS hook.

  Mock: docs/solana/widgets_mocks/cf_inline_landscape_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.CfHelpers

  attr :banner, :map, required: true
  attr :cf_games, :list, default: []

  def cf_inline_landscape(assigns) do
    games_data =
      (assigns.cf_games || [])
      |> Enum.filter(fn g -> g.type in ["win", "loss"] end)
      |> Enum.take(10)
      |> Enum.map(&CfHelpers.format_cf_game/1)

    game = List.first(games_data)

    assigns =
      assigns
      |> assign(:game, game)
      |> assign(:games_json, Jason.encode!(games_data))

    ~H"""
    <a
      href="/play"
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell cf-land block no-underline cursor-pointer"
      phx-hook="CfLiveCycle"
      data-banner-id={@banner.id}
      data-widget-type="cf_inline_landscape"
      data-games={@games_json}
    >
      <%!-- Header --%>
      <div class="cf-land__head">
        <span class="cf-land__brand">
          <span class="cf-land__brand-wordmark bw-display">BL<img class="cf-land__brand-wordmark-o" src={CfHelpers.blockster_icon()} alt="O" />CKSTER</span>
          <span class="cf-land__brand-divider"></span>
          <span class="cf-land__brand-sub bw-display">Coin Flip Live</span>
        </span>
        <span class="cf-land__tagline bw-display">Real-time results from the coin flip game</span>
        <span class="cf-land__head-right">
          <span class="cf-land__live bw-display"><span class="bw-pulse-dot"></span>LIVE</span>
        </span>
      </div>

      <%!-- Body --%>
      <div data-cf-live-body>
        <%= if @game do %>
          <.landscape_game game={@game} />
        <% else %>
          <.landscape_empty />
        <% end %>
      </div>

      <%!-- Footer --%>
      <div class="cf-land__foot">
        <%= if @game do %>
          <span class="cf-land__hook bw-display">
            <span class="bw-pulse-dot" style={if !@game.won, do: "background: var(--bw-red);", else: ""}></span>
            <span class="cf-land__hook-wallet">{@game.wallet_short}</span>
            {if @game.won, do: "just won on Blockster Coin Flip", else: "just lost on Blockster Coin Flip"}
          </span>
        <% else %>
          <span class="cf-land__hook bw-display">
            <span class="bw-pulse-dot"></span>
            Waiting for games...
          </span>
        <% end %>
        <span class="cf-land__cta bw-display">Flip a Coin <span class="cf-land__cta-arrow">→</span></span>
      </div>
    </a>
    """
  end

  defp landscape_game(assigns) do
    ~H"""
    <div class="cf-land__body">
      <div class={"cf-land__left #{if @game.won, do: "cf-land__left--win", else: "cf-land__left--loss"}"}>
        <span class={"cf-land__status #{if @game.won, do: "cf-land__status--win", else: "cf-land__status--loss"} bw-display"}>
          {if @game.won, do: "Winner", else: "House Wins"}
        </span>
        <div class="cf-land__odds bw-mono">{:erlang.float_to_binary(@game.multiplier * 1.0, decimals: 2)}<span class="cf-land__odds-x">×</span></div>
        <p class="cf-land__difficulty bw-display">
          <span class="cf-land__difficulty-mode">{CfHelpers.mode_label(@game.mode)}</span> · {@game.flip_count} {if @game.flip_count == 1, do: "flip", else: "flips"} · {CfHelpers.mode_desc(@game.mode)}
        </p>
      </div>

      <div class="cf-land__right">
        <div class="cf-land__row">
          <span class="cf-land__row-label bw-display">Player's Pick</span>
          <div class="cf-land__coins">
            <%= for pred <- @game.predictions do %>
              <% side = CfHelpers.chip_side(pred) %>
              <span class={"cf-chip cf-chip--lg cf-chip--#{side}"}><span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span></span>
            <% end %>
          </div>
        </div>

        <div class="cf-land__row">
          <span class="cf-land__row-label bw-display">Result</span>
          <div class="cf-land__coins">
            <%= for {res, idx} <- Enum.with_index(@game.results) do %>
              <% side = CfHelpers.chip_side(res) %>
              <% match = CfHelpers.matched?(@game.predictions, @game.results, idx) %>
              <span class={"cf-chip cf-chip--lg cf-chip--#{side} #{if match, do: "cf-chip--match", else: "cf-chip--miss"}"}>
                <span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span>
                <span class={"cf-chip__badge #{if match, do: "cf-chip__badge--ok", else: "cf-chip__badge--no"}"}>{if match, do: "✓", else: "✗"}</span>
              </span>
            <% end %>
          </div>
        </div>

        <div class="cf-land__cards">
          <div class="cf-land__card">
            <p class="cf-land__card-label bw-display">Stake</p>
            <span class="cf-land__card-value bw-mono">
              {CfHelpers.format_sol(@game.bet_amount)}
              <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
              <span class="cf-land__card-ticker bw-display">SOL</span>
            </span>
            <span class="cf-land__card-usd">≈ {CfHelpers.format_usd(@game.usd_stake)}</span>
          </div>
          <div class="cf-land__card">
            <p class="cf-land__card-label bw-display">Net P&amp;L</p>
            <span class={"cf-land__card-value #{if @game.won, do: "cf-land__card-value--pos", else: "cf-land__card-value--neg"} bw-mono"}>
              {CfHelpers.format_net_sol(@game.net)}
              <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
              <span class="cf-land__card-ticker bw-display">SOL</span>
            </span>
            <span class="cf-land__card-usd">≈ {CfHelpers.format_net_usd(@game.usd_net)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp landscape_empty(assigns) do
    ~H"""
    <div class="cf-land__body" style="min-height:240px;">
      <div class="cf-land__left" style="display:flex;align-items:center;justify-content:center;">
        <span class="bw-display text-[11px] font-semibold uppercase tracking-[0.16em] text-[#4B5563]">
          Waiting for games...
        </span>
      </div>
      <div class="cf-land__right" style="display:flex;align-items:center;justify-content:center;">
        <span class="bw-display text-[10px] text-[#4B5563]">
          Live results will appear here
        </span>
      </div>
    </div>
    """
  end
end
