defmodule BlocksterV2Web.Widgets.FsSidebarTileTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsSidebarTile

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 702,
        name: "fs-sidebar-tile-test",
        placement: "sidebar_right",
        widget_type: "fs_sidebar_tile"
      },
      overrides
    )
  end

  defp order(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ord-bull-sb",
        "side" => "buy",
        "filled" => true,
        "status_text" => "ORDER FILLED",
        "token_symbol" => "BULL",
        "sol_amount_ui" => 0.05,
        "payout_ui" => 635.13,
        "payout_usd" => 4.73,
        "sol_usd" => 4.30,
        "discount_pct" => 9.1,
        "profit_ui" => 60.85,
        "profit_pct" => 10.0,
        "profit_usd" => 0.43,
        "fill_chance_pct" => 39.52,
        "settled_at" => System.system_time(:second) - 120
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&FsSidebarTile.fs_sidebar_tile/1, assigns)

  test "renders root with fs_sidebar_tile widget_type + FsHeroWidget hook" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ ~s(data-widget-type="fs_sidebar_tile")
    assert html =~ ~s(phx-hook="FsHeroWidget")
  end

  test "constrained to 200 × 320 dimensions" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "w-[200px]"
    assert html =~ "h-[320px]"
  end

  test "brand header shows FateSwap + Solana DEX + LIVE" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "fateswap.io/images/logo-full.svg"
    assert html =~ "Solana DEX"
    assert html =~ "LIVE"
  end

  test "empty state renders shimmer skeleton when no trades" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "bw-skeleton"
    assert html =~ "fs-sidebar-skeleton"
  end

  test "empty state renders tracker error placeholder when tracker_error? is true" do
    html =
      render_widget(%{
        banner: banner(),
        trades: [],
        selection: nil,
        order_override: nil,
        tracker_error?: true
      })

    assert html =~ "FateSwap feed paused"
    refute html =~ "fs-sidebar-skeleton"
  end

  test "renders status pill + headline + Received/Paid + profit + conviction" do
    html =
      render_widget(%{
        banner: banner(),
        trades: [order()],
        selection: "ord-bull-sb",
        order_override: nil
      })

    assert html =~ "ORDER FILLED"
    assert html =~ "Bought"
    assert html =~ "635.13"
    assert html =~ "BULL"
    assert html =~ "9.10%"
    assert html =~ "discount"
    assert html =~ "Received"
    assert html =~ "Trader Paid"
    assert html =~ "0.0500"
    assert html =~ "Profit"
    assert html =~ "+$0.43"
    assert html =~ "(+10.00%)"
    assert html =~ ~r/left:\d+(\.\d+)?%/
  end

  test "click attributes carry banner + order id" do
    html =
      render_widget(%{
        banner: banner(%{id: 91}),
        trades: [order()],
        selection: "ord-bull-sb",
        order_override: nil
      })

    assert html =~ ~s(data-banner-id="91")
    assert html =~ ~s(data-order-id="ord-bull-sb")
    assert html =~ ~s(phx-value-subject="ord-bull-sb")
  end

  test "sell variant uses Sold verb, premium, Trader Sold" do
    sell =
      order(%{
        "id" => "ord-sell-sb",
        "side" => "sell",
        "discount_pct" => 10.0,
        "payout_ui" => 0.0593
      })

    html = render_widget(%{banner: banner(), trades: [sell], selection: nil, order_override: nil})

    assert html =~ "Sold"
    assert html =~ "premium"
    assert html =~ "Trader Sold"
  end

  test "NOT FILLED variant renders red pill" do
    nf =
      order(%{
        "filled" => false,
        "status_text" => "NOT FILLED",
        "profit_ui" => -0.005,
        "profit_pct" => -10.0,
        "profit_usd" => -0.43
      })

    html = render_widget(%{banner: banner(), trades: [nf], selection: nil, order_override: nil})

    assert html =~ "NOT FILLED"
    assert html =~ "text-[#EF4444]"
  end
end
