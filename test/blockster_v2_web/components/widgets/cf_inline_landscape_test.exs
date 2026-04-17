defmodule BlocksterV2Web.Widgets.CfInlineLandscapeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfInlineLandscape

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 502,
        name: "cf-landscape-live-test",
        placement: "article_inline_1",
        widget_type: "cf_inline_landscape"
      },
      overrides
    )
  end

  defp sample_game(overrides \\ %{}) do
    Map.merge(
      %{
        type: "win",
        difficulty: 2,
        predictions: [:h, :h],
        results: [:h, :h],
        bet_amount: 0.5,
        payout: 1.98,
        wallet: "7k2abcdefghij9fX",
        vault_type: "sol",
        status: :settled,
        created_at: ~U[2026-04-15 02:14:00Z]
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&CfInlineLandscape.cf_inline_landscape/1, assigns)

  test "renders root with cf_inline_landscape widget_type + CfLiveCycle hook" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ ~s(data-widget-type="cf_inline_landscape")
    assert html =~ ~s(phx-hook="CfLiveCycle")
  end

  test "renders as a link to /play" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ ~s(href="/play")
    refute html =~ ~s(target="_blank")
  end

  test "renders empty state when no games" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ "Waiting for games"
  end

  test "renders BL[icon]CKSTER wordmark + LIVE badge" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ "blockster-icon.png"
    assert html =~ "CKSTER"
    assert html =~ "LIVE"
  end

  test "renders two-column layout with game data" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "cf-land__left"
    assert html =~ "cf-land__right"
    assert html =~ "cf-land__left--win"
    assert html =~ "cf-land__status--win"
  end

  test "renders multiplier and difficulty in left panel" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "3.96"
    assert html =~ "cf-land__odds"
    assert html =~ "Win All"
    assert html =~ "all must match"
  end

  test "renders chips with match/miss indicators" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "cf-chip--lg"
    assert html =~ "cf-chip--match"
    assert html =~ "cf-chip__badge--ok"
  end

  test "renders stake and net P&L cards" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Stake"
    assert html =~ "Net P&amp;L"
    assert html =~ "0.50"
    assert html =~ "solana-sol-logo.png"
  end

  test "renders footer with wallet and CTA" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "7k2...9fX"
    assert html =~ "just won on Blockster Coin Flip"
    assert html =~ "Flip a Coin"
  end

  test "loss game renders correctly" do
    loss = %{
      type: "loss",
      difficulty: -2,
      predictions: [:h, :h, :h],
      results: [:t, :t, :t],
      bet_amount: 5.0,
      payout: 0,
      wallet: "D4pxyz123456a1Y",
      vault_type: "sol",
      status: :settled,
      created_at: ~U[2026-04-15 02:02:00Z]
    }

    html = render_widget(%{banner: banner(), cf_games: [loss]})

    assert html =~ "House Wins"
    assert html =~ "cf-land__left--loss"
    assert html =~ "just lost"
  end
end
