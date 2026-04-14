defmodule BlocksterV2.Ads.BannerWidgetTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Ads
  alias BlocksterV2.Ads.Banner

  describe "changeset widget_type / image_url rules" do
    test "image_url required when widget_type is nil" do
      {:error, cs} = Ads.create_banner(%{name: "n", placement: "sidebar_right"})
      assert %{image_url: ["can't be blank"]} = errors_on(cs)
    end

    test "image_url optional when widget_type is set" do
      {:ok, banner} =
        Ads.create_banner(%{
          name: "rt sky",
          placement: "sidebar_right",
          widget_type: "rt_skyscraper"
        })

      assert banner.widget_type == "rt_skyscraper"
      assert banner.image_url in [nil, ""]
      assert banner.widget_config == %{}
    end

    test "widget_type must be in whitelist" do
      {:error, cs} =
        Ads.create_banner(%{
          name: "bad",
          placement: "sidebar_right",
          widget_type: "not_a_real_widget"
        })

      assert %{widget_type: [msg]} = errors_on(cs)
      assert msg =~ "is invalid"
    end

    test "accepts every valid widget_type" do
      for type <- Banner.valid_widget_types() do
        attrs = %{name: "x-#{type}", placement: "sidebar_right", widget_type: type}
        assert {:ok, banner} = Ads.create_banner(attrs)
        assert banner.widget_type == type
      end
    end

    test "widget_config defaults to %{}" do
      {:ok, banner} =
        Ads.create_banner(%{
          name: "n",
          placement: "sidebar_right",
          widget_type: "rt_skyscraper"
        })

      assert banner.widget_config == %{}
    end

    test "widget_config round-trips arbitrary map" do
      config = %{"selection" => "fixed", "bot_id" => "kronos", "timeframe" => "7d"}

      {:ok, banner} =
        Ads.create_banner(%{
          name: "n",
          placement: "sidebar_right",
          widget_type: "rt_chart_landscape",
          widget_config: config
        })

      assert banner.widget_config == config
    end
  end

  describe "Ads.list_widget_banners/0" do
    test "returns only active banners with widget_type" do
      {:ok, _img} =
        Ads.create_banner(%{
          name: "plain",
          placement: "sidebar_right",
          image_url: "https://x/img.png"
        })

      {:ok, widget} =
        Ads.create_banner(%{
          name: "rt",
          placement: "sidebar_right",
          widget_type: "rt_skyscraper"
        })

      {:ok, _inactive_widget} =
        Ads.create_banner(%{
          name: "off",
          placement: "sidebar_right",
          widget_type: "fs_skyscraper",
          is_active: false
        })

      ids = Enum.map(Ads.list_widget_banners(), & &1.id)
      assert widget.id in ids
      assert length(ids) == 1
    end
  end
end
