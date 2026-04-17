defmodule BlocksterV2Web.Widgets.CfSidebarDemoTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.CfSidebarDemo

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 401,
        name: "cf-sidebar-demo-test",
        placement: "sidebar_left",
        widget_type: "cf_sidebar_demo"
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&CfSidebarDemo.cf_sidebar_demo/1, assigns)

  test "renders root with cf_sidebar_demo widget_type" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(data-widget-type="cf_sidebar_demo")
  end

  test "renders as a link to /play (no target _blank — same-tab)" do
    html = render_widget(%{banner: banner()})

    assert html =~ ~s(href="/play")
    refute html =~ ~s(target="_blank")
  end

  test "renders bw-widget bw-shell cf-sb classes" do
    html = render_widget(%{banner: banner()})

    assert html =~ "bw-widget"
    assert html =~ "bw-shell"
    assert html =~ "cf-sb"
  end

  test "renders BL[icon]CKSTER wordmark" do
    html = render_widget(%{banner: banner()})

    assert html =~ "blockster-icon.png"
    assert html =~ "CKSTER"
  end

  test "renders single difficulty: Win All 3 Flips 7.92x" do
    html = render_widget(%{banner: banner()})

    assert html =~ "Win All"
    assert html =~ "3 Flips"
    assert html =~ "7.92"
  end

  test "renders 3 player pick chips (heads, tails, heads)" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-chip--heads"
    assert html =~ "cf-chip--tails"
  end

  test "renders 3D coin zone with 3 slots" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-demo-coin-zone"
    assert html =~ "cf-demo-orbit"
    assert html =~ "cf-demo-slot-1"
    assert html =~ "cf-demo-slot-2"
    assert html =~ "cf-demo-slot-3"
  end

  test "renders 7 status items (spin/hold for 3 flips + win)" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-demo-status-spin1"
    assert html =~ "cf-demo-status-hold1"
    assert html =~ "cf-demo-status-spin2"
    assert html =~ "cf-demo-status-hold2"
    assert html =~ "cf-demo-status-spin3"
    assert html =~ "cf-demo-status-hold3"
    assert html =~ "cf-demo-status-win"
    assert html =~ "You Won!"
  end

  test "renders 3 result slots with placeholder + match chips" do
    html = render_widget(%{banner: banner()})

    assert html =~ "cf-demo-result-1"
    assert html =~ "cf-demo-result-2"
    assert html =~ "cf-demo-result-3"
    assert html =~ "cf-demo-ph-1"
    assert html =~ "cf-demo-ph-2"
    assert html =~ "cf-demo-ph-3"
    assert html =~ "cf-chip--match"
    assert html =~ "cf-chip__badge--ok"
  end

  test "renders stake and winner sections" do
    html = render_widget(%{banner: banner()})

    assert html =~ "Stake"
    assert html =~ "0.50"
    assert html =~ "solana-sol-logo.png"
    assert html =~ "cf-sb__winner"
    assert html =~ "+3.46 SOL"
  end

  test "renders footer tagline" do
    html = render_widget(%{banner: banner()})

    assert html =~ "Flip a Coin"
    assert html =~ "31.68"
  end

  test "does NOT have CfDemoCycle hook (single animation, no cycling)" do
    html = render_widget(%{banner: banner()})

    refute html =~ "CfDemoCycle"
    refute html =~ "data-cf-panel"
  end
end
