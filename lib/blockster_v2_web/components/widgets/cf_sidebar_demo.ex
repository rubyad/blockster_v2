defmodule BlocksterV2Web.Widgets.CfSidebarDemo do
  @moduledoc """
  Coin Flip sidebar demo widget (200 x 340) — single difficulty "how it works"
  animation. Win All · 3 Flips · 7.92×, 18s pure CSS loop. No JS cycling,
  no panels — just the mock's exact HTML/CSS animation.

  Mock: docs/solana/widgets_mocks/cf_sidebar_demo_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.CfHelpers

  attr :banner, :map, required: true

  def cf_sidebar_demo(assigns) do
    sol_price = CfHelpers.get_sol_price()
    stake_usd = if is_number(sol_price), do: "$#{:erlang.float_to_binary(0.50 * sol_price, decimals: 2)}", else: "—"
    win_usd = if is_number(sol_price), do: "+$#{:erlang.float_to_binary(3.46 * sol_price, decimals: 0) |> String.replace(".","")}", else: "—"

    assigns =
      assigns
      |> assign(:stake_usd, stake_usd)
      |> assign(:win_usd, win_usd)

    ~H"""
    <a
      href="/play"
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget bw-shell cf-sb block no-underline cursor-pointer"
      data-banner-id={@banner.id}
      data-widget-type="cf_sidebar_demo"
    >
      <div class="cf-sb__head">
        <span class="cf-sb__brand-wordmark bw-display">BL<img class="cf-sb__brand-wordmark-o" src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="O" />CKSTER</span>
        <span class="cf-sb__head-spacer"></span>
        <span class="cf-sb__sub bw-display"><span class="bw-pulse-dot"></span>Coin Flip</span>
      </div>

      <div class="cf-sb__body">
        <p class="cf-sb__mode-line bw-display">
          Win All · 3 Flips · <span class="cf-sb__odds bw-mono">7.92×</span>
        </p>

        <div class="cf-sb__row">
          <p class="cf-sb__row-label bw-display">Player's Pick</p>
          <div class="cf-sb__coins">
            <span class="cf-chip cf-chip--sb cf-chip--heads"><span class="cf-chip__inner">&#x1F680;</span></span>
            <span class="cf-chip cf-chip--sb cf-chip--tails"><span class="cf-chip__inner">&#x1F4A9;</span></span>
            <span class="cf-chip cf-chip--sb cf-chip--heads"><span class="cf-chip__inner">&#x1F680;</span></span>
          </div>
        </div>

        <div class="cf-sb__coin-area">
          <div class="cf-demo-coin-zone">
            <div class="cf-demo-orbit"></div>
            <div class="cf-demo-slot cf-demo-slot-1">
              <div class="cf-demo-rotator">
                <div class="cf-demo-face cf-demo-face--heads"><span class="cf-demo-face__inner">&#x1F680;</span></div>
                <div class="cf-demo-face cf-demo-face--tails"><span class="cf-demo-face__inner">&#x1F4A9;</span></div>
              </div>
            </div>
            <div class="cf-demo-slot cf-demo-slot-2">
              <div class="cf-demo-rotator">
                <div class="cf-demo-face cf-demo-face--heads"><span class="cf-demo-face__inner">&#x1F680;</span></div>
                <div class="cf-demo-face cf-demo-face--tails"><span class="cf-demo-face__inner">&#x1F4A9;</span></div>
              </div>
            </div>
            <div class="cf-demo-slot cf-demo-slot-3">
              <div class="cf-demo-rotator">
                <div class="cf-demo-face cf-demo-face--heads"><span class="cf-demo-face__inner">&#x1F680;</span></div>
                <div class="cf-demo-face cf-demo-face--tails"><span class="cf-demo-face__inner">&#x1F4A9;</span></div>
              </div>
            </div>
          </div>
        </div>

        <div class="cf-sb__status-wrap">
          <span class="cf-sb__status-item cf-demo-status-spin1 bw-display"><span class="bw-pulse-dot"></span>Flipping · 1 of 3</span>
          <span class="cf-sb__status-item cf-sb__status-item--hold cf-demo-status-hold1 bw-display"><span class="bw-pulse-dot" style="background: var(--bw-lime);"></span>Landed · 1 of 3</span>
          <span class="cf-sb__status-item cf-demo-status-spin2 bw-display"><span class="bw-pulse-dot"></span>Flipping · 2 of 3</span>
          <span class="cf-sb__status-item cf-sb__status-item--hold cf-demo-status-hold2 bw-display"><span class="bw-pulse-dot" style="background: var(--bw-lime);"></span>Landed · 2 of 3</span>
          <span class="cf-sb__status-item cf-demo-status-spin3 bw-display"><span class="bw-pulse-dot"></span>Flipping · 3 of 3</span>
          <span class="cf-sb__status-item cf-sb__status-item--hold cf-demo-status-hold3 bw-display"><span class="bw-pulse-dot" style="background: var(--bw-lime);"></span>Landed · 3 of 3</span>
          <span class="cf-sb__status-item cf-sb__status-item--win cf-demo-status-win bw-display"><span class="bw-pulse-dot"></span>You Won!</span>
        </div>

        <div class="cf-sb__row" style="margin-top: 4px;">
          <p class="cf-sb__row-label bw-display">Result</p>
          <div class="cf-sb__coins">
            <div class="cf-sb__result-slot">
              <span class="cf-chip--placeholder cf-demo-ph-1">?</span>
              <span class="cf-chip cf-chip--sb cf-chip--heads cf-chip--match cf-demo-result-1">
                <span class="cf-chip__inner">&#x1F680;</span>
                <span class="cf-chip__badge cf-chip__badge--ok">&#x2713;</span>
              </span>
            </div>
            <div class="cf-sb__result-slot">
              <span class="cf-chip--placeholder cf-demo-ph-2">?</span>
              <span class="cf-chip cf-chip--sb cf-chip--tails cf-chip--match cf-demo-result-2">
                <span class="cf-chip__inner">&#x1F4A9;</span>
                <span class="cf-chip__badge cf-chip__badge--ok">&#x2713;</span>
              </span>
            </div>
            <div class="cf-sb__result-slot">
              <span class="cf-chip--placeholder cf-demo-ph-3">?</span>
              <span class="cf-chip cf-chip--sb cf-chip--heads cf-chip--match cf-demo-result-3">
                <span class="cf-chip__inner">&#x1F680;</span>
                <span class="cf-chip__badge cf-chip__badge--ok">&#x2713;</span>
              </span>
            </div>
          </div>
        </div>

        <div class="cf-sb__bottom">
          <div class="cf-sb__stats">
            <div>
              <p class="cf-sb__stat-label bw-display">Stake</p>
              <span class="cf-sb__stat-value bw-mono">
                0.50
                <img class="cf-token" src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" />
                <span class="cf-sb__stat-ticker bw-display">SOL</span>
              </span>
              <span class="cf-sb__stat-usd">&asymp; {@stake_usd}</span>
            </div>
            <div style="text-align:right;">
              <p class="cf-sb__stat-label bw-display">Payout</p>
              <span class="cf-sb__stat-value bw-mono" style="justify-content:flex-end;width:100%;color:var(--bw-faint);">
                &mdash;
              </span>
              <span class="cf-sb__stat-usd">&nbsp;</span>
            </div>
          </div>
          <div class="cf-sb__winner">
            <span class="cf-sb__winner-label bw-display">You Won</span>
            <span class="cf-sb__winner-amount bw-mono">
              +3.46 SOL
            </span>
            <span class="cf-sb__winner-usd">&asymp; {@win_usd}</span>
          </div>
        </div>
      </div>

      <div class="cf-sb__foot">
        <span class="cf-sb__tagline bw-display">
          <span class="bw-pulse-dot"></span>Flip a Coin · Win up to 31.68×
        </span>
      </div>
    </a>
    """
  end
end
