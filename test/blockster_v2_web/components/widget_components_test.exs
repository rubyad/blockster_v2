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

  describe "widget_or_ad/1 — raises for real widgets until Phase 3+" do
    for widget_type <- Banner.valid_widget_types() do
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
