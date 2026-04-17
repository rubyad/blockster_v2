defmodule BlocksterV2Web.Widgets.CfSidebarTile do
  @moduledoc """
  Coin Flip sidebar tile (200 x 340) — live widget showing real settled
  game results. Cycles through last 10 SOL games via CfLiveCycle JS hook.

  Mock: docs/solana/widgets_mocks/cf_sidebar_tile_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.CfHelpers

  attr :banner, :map, required: true
  attr :cf_games, :list, default: []

  def cf_sidebar_tile(assigns) do
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
      class="not-prose bw-widget bw-shell cf-sb block no-underline cursor-pointer"
      phx-hook="CfLiveCycle"
      data-banner-id={@banner.id}
      data-widget-type="cf_sidebar_tile"
      data-games={@games_json}
    >
      <%!-- Header --%>
      <div class="cf-sb__head">
        <div class="cf-sb__head-row">
          <span class="cf-sb__brand-wordmark bw-display">BL<img class="cf-sb__brand-wordmark-o" src={CfHelpers.blockster_icon()} alt="O" />CKSTER</span>
          <span class="cf-sb__head-spacer"></span>
          <span class="cf-sb__live bw-display"><span class="bw-pulse-dot"></span>LIVE</span>
        </div>
        <div class="cf-sb__head-row">
          <span class="cf-sb__sub bw-display">Coin Flip</span>
        </div>
      </div>

      <%!-- Body --%>
      <div class="cf-sb__body" data-cf-live-body>
        <%= if @game do %>
          <.sidebar_game game={@game} />
        <% else %>
          <.sidebar_empty />
        <% end %>
      </div>

      <%!-- Footer --%>
      <div class="cf-sb__foot">
        <span class="cf-sb__tagline bw-display">
          <span class="bw-pulse-dot"></span>Provably Fair · On Solana
        </span>
      </div>
    </a>
    """
  end

  defp sidebar_game(assigns) do
    ~H"""
    <span class={"cf-sb__status #{if @game.won, do: "cf-sb__status--win", else: "cf-sb__status--loss"} bw-display"}>
      {if @game.won, do: "Winner", else: "House Wins"}
    </span>

    <p class="cf-sb__sub-heading bw-display">
      {CfHelpers.mode_label(@game.mode)} · {@game.flip_count} {if @game.flip_count == 1, do: "Flip", else: "Flips"} · <span class="cf-sb__odds bw-mono">{:erlang.float_to_binary(@game.multiplier * 1.0, decimals: 2)}×</span>
    </p>

    <%!-- Player's Pick --%>
    <div class="cf-sb__row">
      <p class="cf-sb__row-label bw-display">Player's Pick</p>
      <div class="cf-sb__coins">
        <%= for pred <- @game.predictions do %>
          <% side = CfHelpers.chip_side(pred) %>
          <span class={"cf-chip cf-chip--sb cf-chip--#{side}"}><span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span></span>
        <% end %>
      </div>
    </div>

    <%!-- Result --%>
    <div class="cf-sb__row">
      <p class="cf-sb__row-label bw-display">Result</p>
      <div class="cf-sb__coins">
        <%= for {res, idx} <- Enum.with_index(@game.results) do %>
          <% side = CfHelpers.chip_side(res) %>
          <% match = CfHelpers.matched?(@game.predictions, @game.results, idx) %>
          <span class={"cf-chip cf-chip--sb cf-chip--#{side} #{if match, do: "cf-chip--match", else: "cf-chip--miss"}"}>
            <span class="cf-chip__inner">{CfHelpers.chip_emoji(side)}</span>
            <span class={"cf-chip__badge #{if match, do: "cf-chip__badge--ok", else: "cf-chip__badge--no"}"}>{if match, do: "✓", else: "✗"}</span>
          </span>
        <% end %>
      </div>
    </div>

    <%!-- Stats --%>
    <div class="cf-sb__stats">
      <div>
        <p class="cf-sb__stat-label bw-display">Stake</p>
        <span class="cf-sb__stat-value bw-mono">
          {CfHelpers.format_sol(@game.bet_amount)}
          <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
          <span class="cf-sb__stat-ticker bw-display">SOL</span>
        </span>
        <span class="cf-sb__stat-usd">≈ {CfHelpers.format_usd(@game.usd_stake)}</span>
      </div>
      <div class="cf-sb__stat-col--right">
        <p class="cf-sb__stat-label bw-display">Payout</p>
        <span class={"cf-sb__stat-value #{if @game.won, do: "cf-sb__stat-value--pos", else: "cf-sb__stat-value--neg"} bw-mono"} style="justify-content:flex-end;width:100%;">
          {CfHelpers.format_net_sol(@game.net)}
          <img class="cf-token" src={CfHelpers.sol_logo()} alt="SOL" />
          <span class="cf-sb__stat-ticker bw-display">SOL</span>
        </span>
        <span class="cf-sb__stat-usd">≈ {CfHelpers.format_net_usd(@game.usd_net)}</span>
      </div>
    </div>
    """
  end

  defp sidebar_empty(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center">
        <span class="bw-display text-[10px] font-semibold uppercase tracking-[0.16em] text-[#4B5563]">
          Waiting for games...
        </span>
      </div>
    </div>
    """
  end
end
