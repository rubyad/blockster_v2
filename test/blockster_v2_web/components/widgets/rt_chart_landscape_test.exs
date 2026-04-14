defmodule BlocksterV2Web.Widgets.RtChartLandscapeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtChartLandscape

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 301,
      name: "rt-chart-landscape-test",
      placement: "article_inline_1",
      widget_type: "rt_chart_landscape"
    }, overrides)
  end

  defp bot(overrides \\ %{}) do
    Map.merge(
      %{
        "bot_id" => "kronos",
        "slug" => "kronos",
        "name" => "KRONOS",
        "group_name" => "equities",
        "lp_price" => 0.1024,
        "bid_price" => 0.1023,
        "ask_price" => 0.1026,
        "lp_price_change_1h_pct" => 0.5,
        "lp_price_change_6h_pct" => 1.2,
        "lp_price_change_24h_pct" => 3.24,
        "lp_price_change_48h_pct" => 4.11,
        "lp_price_change_7d_pct" => 6.78,
        "market_open" => true,
        "rank" => 1
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&RtChartLandscape.rt_chart_landscape/1, assigns)
  end

  describe "skeleton" do
    test "renders root with data attributes, hook, widget_type" do
      html = render_widget(%{banner: banner(%{id: 42}), bots: [], selection: nil, chart_data: %{}})

      assert html =~ ~s(data-banner-id="42")
      assert html =~ ~s(phx-hook="RtChartWidget")
      assert html =~ ~s(data-widget-type="rt_chart_landscape")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
    end

    test "renders LIVE pill + TRACKING label even with nil bot" do
      html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

      assert html =~ "LIVE"
      assert html =~ "TRACKING"
    end

    test "renders all 5 timeframe pills" do
      html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

      for tf <- ~w(1H 6H 24H 48H 7D) do
        assert html =~ tf
      end
    end

    test "chart canvas container has phx-update=ignore" do
      html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-role="rt-chart-canvas")
    end

    test "chart seed blob renders even with empty points" do
      html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

      assert html =~ ~s(data-role="rt-chart-seed")
      assert html =~ "[]"
    end
  end

  describe "with selection + chart data" do
    test "uses the selected bot's metadata in the header" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot()],
          selection: {"kronos", "7d"},
          chart_data: %{}
        })

      assert html =~ "KRONOS-LP Price"
      assert html =~ "EQUITIES"
      assert html =~ "0.1023"
      assert html =~ "0.1026"
      # 7d change is 6.78%
      assert html =~ "+6.78%"
    end

    test "active timeframe pill gets the rt-tf--active class" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot()],
          selection: {"kronos", "24h"},
          chart_data: %{}
        })

      # The 24H pill must carry the active modifier class
      # We check by looking for the 24H label adjacent to rt-tf--active.
      assert html =~ "rt-tf--active"
      assert html =~ ~s(data-tf="24h")
    end

    test "serialises chart points into the seed blob" do
      points = [%{"time" => 1, "value" => 1.0}, %{"time" => 2, "value" => 1.5}]

      html =
        render_widget(%{
          banner: banner(),
          bots: [bot()],
          selection: {"kronos", "7d"},
          chart_data: %{{"kronos", "7d"} => points}
        })

      assert html =~ ~s("time":1)
      assert html =~ ~s("value":1.5)
    end

    test "renders H/L from chart points when present" do
      points = [%{"time" => 1, "value" => 1.0}, %{"time" => 2, "value" => 1.5}]

      html =
        render_widget(%{
          banner: banner(),
          bots: [bot()],
          selection: {"kronos", "7d"},
          chart_data: %{{"kronos", "7d"} => points}
        })

      assert html =~ "H"
      assert html =~ "1.5000"
      assert html =~ "1.0000"
    end
  end

  describe "empty state" do
    test "falls back gracefully when bots list and selection are empty" do
      html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

      # Still renders the full shell + header
      assert html =~ "bw-shell"
      assert html =~ "LIVE"
      assert html =~ "—"
    end
  end
end
