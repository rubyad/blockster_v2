defmodule BlocksterV2Web.Widgets.CfPortraitTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfPortrait

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 503,
        name: "cf-portrait-live-test",
        placement: "sidebar_right",
        widget_type: "cf_portrait"
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

  defp render_widget(assigns), do: render_component(&CfPortrait.cf_portrait/1, assigns)

  test "renders root with cf_portrait widget_type + CfLiveCycle hook" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ ~s(data-widget-type="cf_portrait")
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

  test "renders portrait layout with game data" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "cf-port"
    assert html =~ "cf-port__body"
  end

  test "renders winner status and difficulty info" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Winner"
    assert html =~ "Win All"
    assert html =~ "3.96"
  end

  test "renders player picks and results with match badges" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "cf-chip--md"
    assert html =~ "cf-chip--match"
    assert html =~ "cf-chip__badge--ok"
    assert html =~ "Player"
    assert html =~ "Pick"
  end

  test "renders stake and net P&L cards" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Stake"
    assert html =~ "Net P&amp;L"
    assert html =~ "0.50"
    assert html =~ "solana-sol-logo.png"
  end

  test "renders footer with wallet for winner" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "7k2...9fX"
    assert html =~ "just won"
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
    assert html =~ "just lost"
  end

  test "renders games_json data attribute" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ ~s(data-games=)
  end
end
