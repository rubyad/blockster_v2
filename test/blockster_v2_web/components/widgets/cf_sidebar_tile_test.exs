defmodule BlocksterV2Web.Widgets.CfSidebarTileTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfSidebarTile

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 501,
        name: "cf-sidebar-tile-test",
        placement: "sidebar_right",
        widget_type: "cf_sidebar_tile"
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

  defp loss_game do
    %{
      type: "loss",
      difficulty: 3,
      predictions: [:h, :t, :h],
      results: [:h, :t, :t],
      bet_amount: 0.5,
      payout: 0,
      wallet: "D4pxyz123456a1Y",
      vault_type: "sol",
      status: :settled,
      created_at: ~U[2026-04-15 02:02:00Z]
    }
  end

  defp render_widget(assigns), do: render_component(&CfSidebarTile.cf_sidebar_tile/1, assigns)

  test "renders root with cf_sidebar_tile widget_type + CfLiveCycle hook" do
    html = render_widget(%{banner: banner(), cf_games: []})

    assert html =~ ~s(data-widget-type="cf_sidebar_tile")
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

  test "renders winner game with correct status and chips" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Winner"
    assert html =~ "Win All"
    assert html =~ "cf-chip--heads"
    assert html =~ "cf-chip--match"
    assert html =~ "cf-chip__badge--ok"
  end

  test "renders loss game with House Wins status and miss chips" do
    html = render_widget(%{banner: banner(), cf_games: [loss_game()]})

    assert html =~ "House Wins"
    assert html =~ "cf-chip--miss"
    assert html =~ "cf-chip__badge--no"
  end

  test "renders stake and payout with SOL token logo" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Stake"
    assert html =~ "Payout"
    assert html =~ "solana-sol-logo.png"
    assert html =~ "SOL"
    assert html =~ "0.50"
  end

  test "renders truncated wallet in footer" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "Provably Fair"
    assert html =~ "On Solana"
  end

  test "renders games_json data attribute" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ ~s(data-games=)
  end

  test "renders multiplier for win all 2 flips" do
    html = render_widget(%{banner: banner(), cf_games: [sample_game()]})

    assert html =~ "3.96"
  end
end
