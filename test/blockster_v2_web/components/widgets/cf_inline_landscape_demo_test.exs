defmodule BlocksterV2Web.Widgets.CfInlineLandscapeDemoTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfInlineLandscapeDemo

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 402,
        name: "cf-landscape-demo-test",
        placement: "article_inline_1",
        widget_type: "cf_inline_landscape_demo"
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&CfInlineLandscapeDemo.cf_inline_landscape_demo/1, assigns)

  test "renders root with cf_inline_landscape_demo widget_type + CfDemoCycle hook" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(data-widget-type="cf_inline_landscape_demo")
    assert html =~ ~s(phx-hook="CfDemoCycle")
  end

  test "renders as a link to /play" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(href="/play")
    refute html =~ ~s(target="_blank")
  end

  test "renders vw--land landscape class" do
    html = render_widget(%{banner: banner()})

    assert html =~ "vw--land"
  end

  test "renders BL[icon]CKSTER wordmark" do
    html = render_widget(%{banner: banner()})

    assert html =~ "blockster-icon.png"
    assert html =~ "CKSTER"
  end

  test "renders cf-panels-left and cf-panels-right containers" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-panels-left"
    assert html =~ "cf-panels-right"
  end

  test "renders all 9 left panels (p0-p8) with data-cf-panel" do
    html = render_widget(%{banner: banner()})

    # Each panel index appears twice (left + right)
    for idx <- 0..8 do
      assert html =~ ~s(data-cf-panel="#{idx}")
    end
  end

  test "renders 9 indicator dots" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-indicator"
    # 9 dots with data-cf-dot
    assert length(Regex.scan(~r/data-cf-dot/, html)) == 9
  end

  test "renders footer with Provably Fair tag and CTA" do
    html = render_widget(%{banner: banner()})

    assert html =~ "Provably Fair"
    assert html =~ "Settled on Solana"
    assert html =~ "v-cta"
    assert html =~ "Flip a Coin"
  end

  test "renders difficulty info in right panels" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-diff"
    assert html =~ "3.96"
    assert html =~ "Win"
  end

  test "renders stake and payout cards" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-card"
    assert html =~ "Stake"
    assert html =~ "Payout"
  end

  test "renders winner overlays in left panels" do
    html = render_widget(%{banner: banner()})

    assert html =~ "v-winner"
    assert html =~ "You Won"
  end

  test "renders 3D coin zones in left panels" do
    html = render_widget(%{banner: banner()})

    assert html =~ "d-coin-zone"
    assert html =~ "d-face--h"
    assert html =~ "d-face--t"
  end

  test "renders data-cf-cycler on the inner vw div" do
    html = render_widget(%{banner: banner()})

    assert html =~ "data-cf-cycler"
  end

  test "renders data-duration on panels" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(data-duration="9")
    assert html =~ ~s(data-duration="13")
    assert html =~ ~s(data-duration="17")
    assert html =~ ~s(data-duration="21")
    assert html =~ ~s(data-duration="25")
  end
end
