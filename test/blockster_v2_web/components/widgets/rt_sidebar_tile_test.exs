defmodule BlocksterV2Web.Widgets.RtSidebarTileTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtSidebarTile

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 305,
        name: "rt-sidebar-tile-test",
        placement: "sidebar_right",
        widget_type: "rt_sidebar_tile"
      },
      overrides
    )
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
        "lp_price_change_7d_pct" => 3.24
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&RtSidebarTile.rt_sidebar_tile/1, assigns)

  test "renders root with rt_sidebar_tile widget_type + RtSquareCompactWidget hook" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(data-widget-type="rt_sidebar_tile")
    assert html =~ ~s(phx-hook="RtSquareCompactWidget")
  end

  test "constrained to 200 × 340 dimensions" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ "w-[200px]"
    assert html =~ "h-[340px]"
  end

  test "sparkline container has phx-update=ignore + square-canvas seed" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-role="rt-square-canvas")
    assert html =~ ~s(data-role="rt-square-seed")
  end

  test "renders bot name + group + bid/ask + change + H/L when data present" do
    points = [
      %{"time" => 1, "value" => 0.0988},
      %{"time" => 2, "value" => 0.1041},
      %{"time" => 3, "value" => 0.1023}
    ]

    html =
      render_widget(%{
        banner: banner(),
        bots: [bot()],
        selection: {"kronos", "7d"},
        chart_data: %{{"kronos", "7d"} => points}
      })

    assert html =~ "KRONOS"
    assert html =~ "EQUITIES"
    assert html =~ "0.1023"
    assert html =~ "+3.24%"
    assert html =~ "0.1041"
    assert html =~ "0.0988"
  end

  test "empty state renders shell + LIVE" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ "bw-shell"
    assert html =~ "LIVE"
    assert html =~ "AI Trading Bot"
  end
end
