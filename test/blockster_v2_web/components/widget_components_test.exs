defmodule BlocksterV2Web.WidgetComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.WidgetComponents

  describe "widget_or_ad/1 — fallback to ad_banner" do
    test "nil widget_type renders the legacy image ad_banner" do
      banner = %Banner{
        id: 1,
        name: "plain-banner",
        placement: "sidebar_right",
        widget_type: nil,
        template: "image",
        image_url: "https://example.com/plain-banner.png",
        link_url: "https://example.com"
      }

      html = render_component(&WidgetComponents.widget_or_ad/1, %{banner: banner})

      assert html =~ "https://example.com/plain-banner.png"
      assert html =~ ~s(target="_blank")
    end
  end

  describe "widget_or_ad/1 — implemented widgets render" do
    test "rt_skyscraper renders the component with data attributes" do
      banner = %Banner{
        id: 42,
        name: "widget-rt-skyscraper",
        placement: "sidebar_right",
        widget_type: "rt_skyscraper"
      }

      html = render_component(&WidgetComponents.widget_or_ad/1, %{banner: banner, bots: []})

      assert html =~ ~s(data-banner-id="42")
      assert html =~ ~s(phx-hook="RtSkyscraperWidget")
      assert html =~ ~s(phx-value-subject="rt")
    end

    test "fs_skyscraper renders the component with data attributes" do
      banner = %Banner{
        id: 43,
        name: "widget-fs-skyscraper",
        placement: "sidebar_left",
        widget_type: "fs_skyscraper"
      }

      html = render_component(&WidgetComponents.widget_or_ad/1, %{banner: banner, trades: []})

      assert html =~ ~s(data-banner-id="43")
      assert html =~ ~s(phx-hook="FsSkyscraperWidget")
      assert html =~ ~s(phx-value-subject="fs")
    end

    test "rt_chart_landscape renders with RtChartWidget hook" do
      banner = %Banner{
        id: 44,
        name: "widget-rt-chart-landscape",
        placement: "article_inline_1",
        widget_type: "rt_chart_landscape"
      }

      html =
        render_component(&WidgetComponents.widget_or_ad/1, %{
          banner: banner,
          bots: [],
          selections: %{},
          chart_data: %{}
        })

      assert html =~ ~s(data-banner-id="44")
      assert html =~ ~s(phx-hook="RtChartWidget")
      assert html =~ ~s(data-widget-type="rt_chart_landscape")
    end

    test "rt_chart_portrait renders with RtChartWidget hook" do
      banner = %Banner{
        id: 45,
        name: "widget-rt-chart-portrait",
        placement: "article_inline_1",
        widget_type: "rt_chart_portrait"
      }

      html =
        render_component(&WidgetComponents.widget_or_ad/1, %{
          banner: banner,
          bots: [],
          selections: %{},
          chart_data: %{}
        })

      assert html =~ ~s(data-banner-id="45")
      assert html =~ ~s(data-widget-type="rt_chart_portrait")
    end

    test "rt_full_card renders with RtChartWidget hook" do
      banner = %Banner{
        id: 46,
        name: "widget-rt-full-card",
        placement: "article_inline_1",
        widget_type: "rt_full_card"
      }

      html =
        render_component(&WidgetComponents.widget_or_ad/1, %{
          banner: banner,
          bots: [],
          selections: %{},
          chart_data: %{}
        })

      assert html =~ ~s(data-banner-id="46")
      assert html =~ ~s(data-widget-type="rt_full_card")
    end

    test "rt_square_compact renders with its dedicated hook" do
      banner = %Banner{
        id: 47,
        name: "widget-rt-square-compact",
        placement: "sidebar_right",
        widget_type: "rt_square_compact"
      }

      html =
        render_component(&WidgetComponents.widget_or_ad/1, %{
          banner: banner,
          bots: [],
          selections: %{},
          chart_data: %{}
        })

      assert html =~ ~s(data-banner-id="47")
      assert html =~ ~s(phx-hook="RtSquareCompactWidget")
      assert html =~ ~s(data-widget-type="rt_square_compact")
    end
  end

  describe "widget_or_ad/1 — raises for widgets landing in Phase 5+" do
    @phase_5_plus Banner.valid_widget_types() --
                    [
                      "rt_skyscraper",
                      "fs_skyscraper",
                      "rt_chart_landscape",
                      "rt_chart_portrait",
                      "rt_full_card",
                      "rt_square_compact"
                    ]

    for widget_type <- @phase_5_plus do
      @tag widget_type: widget_type
      test "raises for widget_type=#{widget_type}", %{widget_type: widget_type} do
        banner = %Banner{
          id: 42,
          name: "widget-#{widget_type}",
          placement: "sidebar_right",
          widget_type: widget_type
        }

        assert_raise ArgumentError,
                     ~r/widget component not yet implemented \(Phase 3\+\): #{widget_type}/,
                     fn ->
                       render_component(&WidgetComponents.widget_or_ad/1, %{banner: banner})
                     end
      end
    end

    test "raises for an unrecognised widget_type" do
      banner = %Banner{
        id: 99,
        name: "bogus",
        placement: "sidebar_right",
        widget_type: "totally_not_a_widget"
      }

      assert_raise ArgumentError, ~r/unknown widget_type/, fn ->
        render_component(&WidgetComponents.widget_or_ad/1, %{banner: banner})
      end
    end
  end
end
