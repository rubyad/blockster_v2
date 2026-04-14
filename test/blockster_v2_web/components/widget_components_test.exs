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

  describe "widget_or_ad/1 — Phase 3 widgets render" do
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
  end

  describe "widget_or_ad/1 — raises for widgets landing in Phase 4+" do
    @phase_4_plus Banner.valid_widget_types() -- ["rt_skyscraper", "fs_skyscraper"]

    for widget_type <- @phase_4_plus do
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
