defmodule BlocksterV2Web.Widgets.RtChartPortraitTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtChartPortrait

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 302,
      name: "rt-chart-portrait-test",
      placement: "article_inline_1",
      widget_type: "rt_chart_portrait"
    }, overrides)
  end

  defp bot(overrides \\ %{}) do
    Map.merge(
      %{
        "bot_id" => "apollo",
        "slug" => "apollo",
        "name" => "APOLLO",
        "group_name" => "crypto",
        "bid_price" => 0.5012,
        "ask_price" => 0.5025,
        "lp_price_change_24h_pct" => -2.5
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&RtChartPortrait.rt_chart_portrait/1, assigns)
  end

  test "renders root with portrait widget_type + hook" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(data-widget-type="rt_chart_portrait")
    assert html =~ ~s(phx-hook="RtChartWidget")
  end

  test "renders 5 tf pills in a full-width row" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    for tf <- ~w(1H 6H 24H 48H 7D) do
      assert html =~ tf
    end
  end

  test "resolves bot + change pct from selection" do
    html =
      render_widget(%{
        banner: banner(),
        bots: [bot()],
        selection: {"apollo", "24h"},
        chart_data: %{}
      })

    assert html =~ "APOLLO-LP Price"
    assert html =~ "CRYPTO"
    # Negative change renders with the minus unicode
    assert html =~ "−2.50%"
  end

  test "chart container is phx-update=ignore with canvas role" do
    html = render_widget(%{banner: banner(), bots: [], selection: nil, chart_data: %{}})

    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-role="rt-chart-canvas")
  end
end
