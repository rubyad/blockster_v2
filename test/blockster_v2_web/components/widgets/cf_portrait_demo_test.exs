defmodule BlocksterV2Web.Widgets.CfPortraitDemoTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfPortraitDemo

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 403,
        name: "cf-portrait-demo-test",
        placement: "sidebar_right",
        widget_type: "cf_portrait_demo"
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&CfPortraitDemo.cf_portrait_demo/1, assigns)

  test "renders root with cf_portrait_demo widget_type + CfDemoCycle hook" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(data-widget-type="cf_portrait_demo")
    assert html =~ ~s(phx-hook="CfDemoCycle")
  end

  test "renders as a link to /play" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(href="/play")
    refute html =~ ~s(target="_blank")
  end

  test "renders BL[icon]CKSTER wordmark" do
    html = render_widget(%{banner: banner()})

    assert html =~ "blockster-icon.png"
    assert html =~ "CKSTER"
  end

  test "renders .vw class but NOT .vw--land" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(class="vw")
    refute html =~ "vw--land"
  end

  test "renders all 9 panels with data-cf-panel" do
    html = render_widget(%{banner: banner()})

    for i <- 0..8 do
      assert html =~ ~s(data-cf-panel="#{i}")
    end
  end

  test "renders indicator dots" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-indicator"
    assert html =~ "data-cf-dot"
  end

  test "renders footer with Provably Fair and CTA" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-foot"
    assert html =~ "Provably Fair"
    assert html =~ "Flip a Coin"
  end

  test "renders difficulty info for all modes" do
    html = render_widget(%{banner: banner()})

    # Win All modes
    assert html =~ "1.98"
    assert html =~ "3.96"
    assert html =~ "7.92"
    assert html =~ "15.84"
    assert html =~ "31.68"
    # Win One modes
    assert html =~ "1.32"
    assert html =~ "1.13"
    assert html =~ "1.05"
    assert html =~ "1.02"
  end

  test "renders winner overlays with amounts" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-winner"
    assert html =~ "v-winner-label"
    assert html =~ "You Won"
    assert html =~ "v-winner-amount"
  end

  test "renders 3D coin zones" do
    html = render_widget(%{banner: banner()})

    assert html =~ "d-coin-zone"
    assert html =~ "d-orbit"
    assert html =~ "d-face--h"
    assert html =~ "d-face--t"
  end

  test "renders data-cf-cycler on root .vw div" do
    html = render_widget(%{banner: banner()})

    assert html =~ "data-cf-cycler"
  end

  test "renders match and miss result chips" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-chip--match"
    assert html =~ "v-chip--miss"
    assert html =~ "v-badge--ok"
    assert html =~ "v-badge--no"
  end

  test "renders stake and payout cards" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-cards"
    assert html =~ "Stake"
    assert html =~ "Payout"
    assert html =~ "v-card-val--pos"
  end

  test "renders banner id in widget id" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(id="widget-403")
    assert html =~ ~s(data-banner-id="403")
  end
end
