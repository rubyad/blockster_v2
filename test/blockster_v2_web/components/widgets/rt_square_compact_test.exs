defmodule BlocksterV2Web.Widgets.RtSquareCompactTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtSquareCompact

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 304,
      name: "rt-square-compact-test",
      placement: "sidebar_right",
      widget_type: "rt_square_compact"
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
        "lp_price_change_24h_pct" => 3.24
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&RtSquareCompact.rt_square_compact/1, assigns)
  end

  test "renders root with rt_square_compact widget_type + dedicated hook" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(data-widget-type="rt_square_compact")
    assert html =~ ~s(phx-hook="RtSquareCompactWidget")
  end

  test "constrained to 200 × 200 dimensions" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ "w-[200px]"
    assert html =~ "h-[200px]"
  end

  test "sparkline container has phx-update=ignore" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-role="rt-square-canvas")
    assert html =~ ~s(data-role="rt-square-seed")
  end

  test "renders bot name + group tag + price when bot is present" do
    html =
      render_widget(%{
        banner: banner(),
        bots: [bot()],
        selection: {"kronos", "24h"},
        chart_data: %{}
      })

    assert html =~ "KRONOS"
    assert html =~ "EQUITIES"
    assert html =~ "0.1023"
    assert html =~ "+3.24%"
  end

  test "empty state with nil bot renders the shell" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ "bw-shell"
    assert html =~ "LIVE"
    assert html =~ "AI Trading Bot"
  end
end
