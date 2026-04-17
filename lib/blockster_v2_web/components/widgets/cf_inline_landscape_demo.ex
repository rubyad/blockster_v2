defmodule BlocksterV2Web.Widgets.CfInlineLandscapeDemo do
  @moduledoc """
  Coin Flip landscape demo widget (full-width) — animated "how it works"
  cycling through all 9 difficulty levels. Two-column layout: left shows
  the spinning coin + winner banner, right shows picks, results, and payout.
  JS hook (CfDemoCycle) syncs left+right panel transitions.

  Mock: docs/solana/widgets_mocks/cf_landscape_demo_cycling_mock.html
  """

  use Phoenix.Component

  alias BlocksterV2Web.Widgets.CfHelpers

  defp usd(sol_amount, price) when is_number(price) and price > 0 do
    val = sol_amount * price
    formatted = if val >= 1000, do: "#{trunc(val) |> Integer.to_string() |> add_commas()}", else: :erlang.float_to_binary(val * 1.0, decimals: 1)
    if sol_amount >= 0, do: "+$#{formatted}", else: "-$#{formatted}"
  end
  defp usd(_sol_amount, _price), do: "—"

  defp add_commas(str) do
    str |> String.reverse() |> String.to_charlist() |> Enum.chunk_every(3) |> Enum.join(",") |> String.reverse()
  end

  attr :banner, :map, required: true

  def cf_inline_landscape_demo(assigns) do
    sol_price = CfHelpers.get_sol_price()

    assigns =
      assigns
      |> assign_new(:icon, fn -> "https://ik.imagekit.io/blockster/blockster-icon.png" end)
      |> assign_new(:sol, fn -> "https://ik.imagekit.io/blockster/solana-sol-logo.png" end)
      |> assign(:p, sol_price)
      # Stake USD per panel
      |> assign(:s0, usd(1.00, sol_price))
      |> assign(:s1, usd(0.50, sol_price))
      |> assign(:s2, usd(0.50, sol_price))
      |> assign(:s3, usd(0.25, sol_price))
      |> assign(:s4, usd(0.10, sol_price))
      |> assign(:s5, usd(2.00, sol_price))
      |> assign(:s6, usd(5.00, sol_price))
      |> assign(:s7, usd(10.00, sol_price))
      |> assign(:s8, usd(10.00, sol_price))
      # Winner payout USD per panel
      |> assign(:w0, usd(0.98, sol_price))
      |> assign(:w1, usd(1.48, sol_price))
      |> assign(:w2, usd(3.46, sol_price))
      |> assign(:w3, usd(3.71, sol_price))
      |> assign(:w4, usd(3.07, sol_price))
      |> assign(:w5, usd(0.64, sol_price))
      |> assign(:w6, usd(0.65, sol_price))
      |> assign(:w7, usd(0.50, sol_price))
      |> assign(:w8, usd(0.20, sol_price))

    ~H"""
    <a
      href="/play"
      id={"widget-#{@banner.id}"}
      class="not-prose bw-widget cfd block no-underline cursor-pointer"
      phx-hook="CfDemoCycle"
      phx-update="ignore"
      data-banner-id={@banner.id}
      data-widget-type="cf_inline_landscape_demo"
    >
      <div class="vw vw--land" data-cf-cycler>
      <div class="v-head">
        <span class="v-wm bd" style="font-size:18px">BL<img class="v-wm-o" src={@icon} alt="O" style="width:16px;height:16px"/>CKSTER</span>
        <span style="width:1px;height:20px;background:var(--brd2);flex-shrink:0"></span>
        <span class="v-sub bd">Coin Flip</span>
        <span class="v-head-spacer"></span>
        <span class="v-head-spacer"></span>
        <span class="v-sub bd" style="color:var(--grn)"><span class="pulse"></span> LIVE</span>
      </div>
      <div class="v-body">
        <div class="cf-panels-left">
          <div class="cf-indicator" style="position:absolute;top:10px;left:0;right:0"><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span><span class="cf-dot" data-cf-dot></span></div>
<div class="p0 cf-panel" data-cf-panel="0" data-duration="9">
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+0.98 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w0} &middot; 1.98&times;</span>
              </div>
            </div>
          </div>
<div class="p1 cf-panel" data-cf-panel="1" data-duration="13" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/2</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/2</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/2</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/2</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+1.48 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w1} &middot; 3.96&times;</span>
              </div>
            </div>
          </div>
<div class="p2 cf-panel" data-cf-panel="2" data-duration="17" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/3</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/3</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/3</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/3</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/3</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/3</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+3.46 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w2} &middot; 7.92&times;</span>
              </div>
            </div>
          </div>
<div class="p3 cf-panel" data-cf-panel="3" data-duration="21" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-4"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/4</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/4</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/4</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/4</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/4</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/4</span><span class="v-st d-st-s4"><span class="pulse"></span>Flipping &middot; 4/4</span><span class="v-st v-st--hold d-st-h4"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 4/4</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+3.71 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w3} &middot; 15.84&times;</span>
              </div>
            </div>
          </div>
<div class="p4 cf-panel" data-cf-panel="4" data-duration="25" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-4"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-5"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/5</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/5</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/5</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/5</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/5</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/5</span><span class="v-st d-st-s4"><span class="pulse"></span>Flipping &middot; 4/5</span><span class="v-st v-st--hold d-st-h4"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 4/5</span><span class="v-st d-st-s5"><span class="pulse"></span>Flipping &middot; 5/5</span><span class="v-st v-st--hold d-st-h5"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 5/5</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+3.07 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w4} &middot; 31.68&times;</span>
              </div>
            </div>
          </div>
<div class="p5 cf-panel" data-cf-panel="5" data-duration="13" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/2</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/2</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/2</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/2</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+0.64 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w5} &middot; 1.32&times;</span>
              </div>
            </div>
          </div>
<div class="p6 cf-panel" data-cf-panel="6" data-duration="17" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/3</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/3</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/3</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/3</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/3</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/3</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+0.65 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w6} &middot; 1.13&times;</span>
              </div>
            </div>
          </div>
<div class="p7 cf-panel" data-cf-panel="7" data-duration="17" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/4</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/4</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/4</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/4</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/4</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/4</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+0.5 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w7} &middot; 1.05&times;</span>
              </div>
            </div>
          </div>
<div class="p8 cf-panel" data-cf-panel="8" data-duration="17" data-hidden>
            <div class="v-coin-area">
              <div class="d-coin-zone"><div class="d-orbit"></div><div class="d-slot d-slot-1"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-2"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div><div class="d-slot d-slot-3"><div class="d-rot"><div class="d-face d-face--h"><span class="d-face-in">&#x1F680;</span></div><div class="d-face d-face--t"><span class="d-face-in">&#x1F4A9;</span></div></div></div></div>
              <div class="v-st-wrap"><span class="v-st d-st-s1"><span class="pulse"></span>Flipping &middot; 1/5</span><span class="v-st v-st--hold d-st-h1"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 1/5</span><span class="v-st d-st-s2"><span class="pulse"></span>Flipping &middot; 2/5</span><span class="v-st v-st--hold d-st-h2"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 2/5</span><span class="v-st d-st-s3"><span class="pulse"></span>Flipping &middot; 3/5</span><span class="v-st v-st--hold d-st-h3"><span class="pulse" style="background:var(--lime)"></span>Landed &middot; 3/5</span><span class="v-st v-st--win d-st-win"><span class="pulse"></span>Settled on Solana</span></div>
              <div class="v-winner">
                <span class="v-winner-label bd">You Won</span>
                <span class="v-winner-amount bm">+0.2 <img class="v-token" src={@sol} alt="SOL"/> SOL</span>
                <span class="v-winner-usd bm">&asymp; {@w8} &middot; 1.02&times;</span>
              </div>
            </div>
          </div>
        </div>
        <div class="cf-panels-right">
<div class="p0 cf-panel" data-cf-panel="0" data-duration="9">
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">All</span></span><span class="v-diff-dot">&middot;</span><span>1 flip</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">1.98&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:10px"><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:10px"><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-1" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-1" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">1.00 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s0}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+0.98 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w0}</span></div></div></div>
            </div>
          </div>
<div class="p1 cf-panel" data-cf-panel="1" data-duration="13" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">All</span></span><span class="v-diff-dot">&middot;</span><span>2 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">3.96&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:10px"><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:10px"><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-1" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-1" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-2" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-2" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">0.50 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s1}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+1.48 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w1}</span></div></div></div>
            </div>
          </div>
<div class="p2 cf-panel" data-cf-panel="2" data-duration="17" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">All</span></span><span class="v-diff-dot">&middot;</span><span>3 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">7.92&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:10px"><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span><span class="v-chip v-chip--tails" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F4A9;</span></span><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:10px"><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-1" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-1" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-2" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--tails v-chip--match d-res-2" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F4A9;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-3" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">0.50 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s2}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+3.46 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w2}</span></div></div></div>
            </div>
          </div>
<div class="p3 cf-panel" data-cf-panel="3" data-duration="21" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">All</span></span><span class="v-diff-dot">&middot;</span><span>4 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">15.84&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:8px"><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--tails" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--tails" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:8px"><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-1" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-1" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-2" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--match d-res-2" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-3" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-4" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--match d-res-4" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">0.25 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s3}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+3.71 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w3}</span></div></div></div>
            </div>
          </div>
<div class="p4 cf-panel" data-cf-panel="4" data-duration="25" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">All</span></span><span class="v-diff-dot">&middot;</span><span>5 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">31.68&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:8px"><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--tails" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--tails" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:8px"><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-1" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-1" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-2" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--match d-res-2" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-3" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-4" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--match d-res-4" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-5" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-5" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">0.10 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s4}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+3.07 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w4}</span></div></div></div>
            </div>
          </div>
<div class="p5 cf-panel" data-cf-panel="5" data-duration="13" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">One</span></span><span class="v-diff-dot">&middot;</span><span>2 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">1.32&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:10px"><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:10px"><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-1" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-1" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-2" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-2" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">2.00 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s5}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+0.64 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w5}</span></div></div></div>
            </div>
          </div>
<div class="p6 cf-panel" data-cf-panel="6" data-duration="17" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">One</span></span><span class="v-diff-dot">&middot;</span><span>3 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">1.13&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:10px"><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:10px"><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-1" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-1" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-2" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-2" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:42px;height:42px"><span class="v-chip--ph d-ph-3" style="width:42px;height:42px;font-size:16px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:42px;height:42px"><span class="v-chip-in" style="width:28px;height:28px;font-size:18px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">5.00 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s6}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+0.65 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w6}</span></div></div></div>
            </div>
          </div>
<div class="p7 cf-panel" data-cf-panel="7" data-duration="17" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">One</span></span><span class="v-diff-dot">&middot;</span><span>4 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">1.05&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:8px"><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:8px"><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-1" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-1" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-2" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-2" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-3" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph" style="width:36px;height:36px;font-size:13px">?</span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">10.00 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s7}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+0.5 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w7}</span></div></div></div>
            </div>
          </div>
<div class="p8 cf-panel" data-cf-panel="8" data-duration="17" data-hidden>
            <div class="v-diff bd"><span class="v-diff-mode">Win <span class="v-diff-accent">One</span></span><span class="v-diff-dot">&middot;</span><span>5 flips</span><span class="v-diff-dot">&middot;</span><span class="v-diff-odds bm">1.02&times;</span></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Player's Pick</span><div class="v-chips" style="gap:8px"><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span><span class="v-chip v-chip--heads" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span></span></div></div>
            <div style="display:flex;align-items:center;gap:14px"><span style="font-size:9.5px;letter-spacing:0.2em;text-transform:uppercase;font-weight:700;color:var(--sec);width:92px;flex-shrink:0">Result</span><div class="v-chips" style="gap:8px"><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-1" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-1" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-2" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--tails v-chip--miss d-res-2" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F4A9;</span><span class="v-badge v-badge--no">&#x2717;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph d-ph-3" style="width:36px;height:36px;font-size:13px">?</span><span class="v-chip v-chip--heads v-chip--match d-res-3" style="width:36px;height:36px"><span class="v-chip-in" style="width:24px;height:24px;font-size:15px">&#x1F680;</span><span class="v-badge v-badge--ok">&#x2713;</span></span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph" style="width:36px;height:36px;font-size:13px">?</span></div><div class="v-res-slot" style="width:36px;height:36px"><span class="v-chip--ph" style="width:36px;height:36px;font-size:13px">?</span></div></div></div>
            <div class="v-cards">
              <div class="v-card"><p class="v-card-label bd">Stake</p><span class="v-card-val bm">10.00 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm">&asymp; {@s8}</span></div>
              <div class="v-card v-card--pay"><p class="v-card-label bd">Payout</p><div class="v-pay-stack"><span class="v-card-val v-card-val--muted bm d-pay-ph">&mdash;</span><div class="d-pay-val" style="opacity:0"><span class="v-card-val v-card-val--pos bm">+0.2 <img class="v-token" src={@sol} alt="SOL"/> <span class="v-card-ticker bd">SOL</span></span><span class="v-card-usd bm" style="margin-top:6px">&asymp; {@w8}</span></div></div></div>
            </div>
          </div>
        </div>
      </div>
      <div class="v-foot">
        <span class="v-foot-tag bd" style="font-size:9px;letter-spacing:0.18em"><span style="font-size:9px;font-weight:800;letter-spacing:0.18em;text-transform:uppercase;color:var(--lime);background:rgba(202,252,0,0.08);border:1px solid rgba(202,252,0,0.22);padding:4px 8px;border-radius:4px">Provably Fair</span> SHA-256 &middot; Settled on Solana</span>
        <span class="v-cta bd">Flip a Coin &rarr;</span>
      </div>
      </div>
    </a>
    """
  end
end
