defmodule BlocksterV2Web.Widgets.RtFullCardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtFullCard

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 303,
      name: "rt-full-card-test",
      placement: "article_inline_1",
      widget_type: "rt_full_card"
    }, overrides)
  end

  defp bot(overrides \\ %{}) do
    Map.merge(
      %{
        "bot_id" => "kronos",
        "slug" => "kronos",
        "name" => "KRONOS",
        "group_name" => "equities",
        "bid_price" => 0.1023,
        "ask_price" => 0.1026,
        "lp_price_change_7d_pct" => 6.78,
        "sol_balance_ui" => 248.36,
        "lp_supply" => 2_100_000,
        "rank" => 1,
        "counterparty_locked_sol" => 12.4,
        "wins_settled_7d" => %{"wins" => 142, "total" => 181},
        "win_rate" => 78.5,
        "volume_7d_sol" => 2418,
        "avg_stake_7d_sol" => 13.36
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&RtFullCard.rt_full_card/1, assigns)
  end

  test "renders root with rt_full_card widget_type + hook" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(data-widget-type="rt_full_card")
    assert html =~ ~s(phx-hook="RtChartWidget")
  end

  test "renders 8 stat cards with labels from the mock" do
    html =
      render_widget(%{
        banner: banner(),
        bots: [bot()],
        selection: {"kronos", "7d"},
        chart_data: %{}
      })

    # data-role on each card
    assert Enum.count(String.split(html, ~s(data-role="rt-stat-card"))) - 1 == 8

    # Labels
    assert html =~ "AUM"
    assert html =~ "LP Supply"
    assert html =~ "Rank"
    assert html =~ "CP Liability"
    assert html =~ "Wins/Settled"
    assert html =~ "Win Rate"
    assert html =~ "Volume"
    assert html =~ "Avg Stake"
  end

  test "stat values come from the bot snapshot" do
    html =
      render_widget(%{
        banner: banner(),
        bots: [bot()],
        selection: {"kronos", "7d"},
        chart_data: %{}
      })

    # AUM — 248.36 SOL
    assert html =~ "248.36"
    # LP Supply — formatted with commas (2,100,000)
    assert html =~ "2,100,000"
    # Rank — "1" with only whitespace on the line inside its stat card div
    assert Regex.match?(~r/\s1\s*<\/div>/, html)
    # Wins/Settled
    assert html =~ "142/181"
    # Win rate
    assert html =~ "78.5%"
    # CP Liability
    assert html =~ "12.40"
  end

  test "chart container is phx-update=ignore with canvas role" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-role="rt-chart-canvas")
  end
end
