defmodule BlocksterV2Web.Widgets.CfPortrait do
  @moduledoc """
  Coin Flip portrait live widget (400px wide × auto) — vertical layout showing
  real settled game results. Cycles through last 10 SOL games via CfLiveCycle JS hook.

  Mock: reuses portrait structure from cf_portrait_demo_cycling_mock.html but with live data.
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.CfHelpers

  attr :banner, :map, required: true
  attr :cf_games, :list, default: []

  def cf_portrait(assigns) do
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
      class="not-prose bw-widget bw-shell cf-port block no-underline cursor-pointer"
      phx-hook="CfLiveCycle"
      data-banner-id={@banner.id}
      data-widget-type="cf_portrait"
      data-games={@games_json}
    >
      <%!-- Header --%>
      <div class="cf-port__head">
        <span class="cf-port__brand-wordmark bw-display">BL<img class="cf-port__brand-wordmark-o" src={CfHelpers.blockster_icon()} alt="O" />CKSTER</span>
        <span style="flex:1;"></span>
        <span class="cf-port__live bw-display"><span class="bw-pulse-dot"></span>LIVE</span>
      </div>

      <%!-- Body --%>
      <div class="cf-port__body" data-cf-live-body>
        <%= if @game do %>
          <.portrait_game game={@game} />
        <% else %>
          <.portrait_empty />
        <% end %>
      </div>

      <%!-- Footer --%>
      <div class="cf-port__foot">
        <%= if @game do %>
          <span class="cf-port__hook bw-display">
            <span class="bw-pulse-dot" style={if !@game.won, do: "background: var(--bw-red);", else: ""}></span>
            <span class="cf-port__hook-wallet bw-mono">{@game.wallet_short}</span>
            {if @game.won, do: "just won", else: "just lost"}
          </span>
        <% else %>
          <span class="cf-port__tagline bw-display">
            <span class="bw-pulse-dot"></span>Provably Fair · On Solana
          </span>
        <% end %>
      </div>
    </a>
    """
  end

  defp portrait_game(assigns) do
    ~H"""
    <%!-- Status pill --%>
    <span class={"cf-port__status #{if @game.won, do: "cf-port__status--win", else: "cf-port__status--loss"} bw-display"}>
      {if @game.won, do: "Winner", else: "House Wins"}
    </span>

    <%!-- Difficulty line --%>
    <div class="cf-port__diff bw-display">
      <span class="cf-port__diff-mode">{CfHelpers.mode_label(@game.mode)}</span>
      <span class="cf-port__diff-dot">·</span>
      {@game.flip_count} {if @game.flip_count == 1, do: "Flip", else: "Flips"}
      <span class="cf-port__diff-dot">·</span>
      <span class="cf-port__diff-odds bw-mono">{:erlang.float_to_binary(@game.multiplier * 1.0, decimals: 2)}×</span>
    </div>

    <%!-- Player's Pick --%>
    <div class="cf-port__row">
      <p class="cf-port__row-label bw-display">Player's Pick</p>
      <div class="cf-port__coins">
        <%= for pred <- @game.predictions do %>
          <% side = CfHelpers.chip_side(pred) %>
          <span class={"cf-chip cf-chip--md cf-chip--#{side}"}><span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span></span>
        <% end %>
      </div>
    </div>

    <%!-- Result --%>
    <div class="cf-port__row">
      <p class="cf-port__row-label bw-display">Result</p>
      <div class="cf-port__coins">
        <%= for {res, idx} <- Enum.with_index(@game.results) do %>
          <% side = CfHelpers.chip_side(res) %>
          <% match = CfHelpers.matched?(@game.predictions, @game.results, idx) %>
          <span class={"cf-chip cf-chip--md cf-chip--#{side} #{if match, do: "cf-chip--match", else: "cf-chip--miss"}"}>
            <span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span>
            <span class={"cf-chip__badge #{if match, do: "cf-chip__badge--ok", else: "cf-chip__badge--no"}"}>{if match, do: "✓", else: "✗"}</span>
          </span>
        <% end %>
      </div>
    </div>

    <%!-- Cards: stake + net P&L --%>
    <div class="cf-port__cards">
      <div class="cf-port__card">
        <p class="cf-port__card-label bw-display">Stake</p>
        <span class="cf-port__card-value bw-mono">
          {CfHelpers.format_sol(@game.bet_amount)}
          <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
          <span class="cf-port__card-ticker bw-display">SOL</span>
        </span>
        <span class="cf-port__card-usd">≈ {CfHelpers.format_usd(@game.usd_stake)}</span>
      </div>
      <div class="cf-port__card">
        <p class="cf-port__card-label bw-display">Net P&amp;L</p>
        <span class={"cf-port__card-value #{if @game.won, do: "cf-port__card-value--pos", else: "cf-port__card-value--neg"} bw-mono"}>
          {CfHelpers.format_net_sol(@game.net)}
          <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
          <span class="cf-port__card-ticker bw-display">SOL</span>
        </span>
        <span class="cf-port__card-usd">≈ {CfHelpers.format_net_usd(@game.usd_net)}</span>
      </div>
    </div>
    """
  end

  defp portrait_empty(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center py-12">
      <div class="text-center">
        <span class="bw-display text-[10px] font-semibold uppercase tracking-[0.16em] text-[#4B5563]">
          Waiting for games...
        </span>
        <div class="bw-display text-[10px] text-[#4B5563] mt-1">
          Live results will appear here
        </div>
      </div>
    </div>
    """
  end
end
