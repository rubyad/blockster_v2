defmodule BlocksterV2Web.Widgets.FsSquareCompactTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsSquareCompact

  defp banner(overrides \\ %{}) do
    struct(
      %Banner{
        id: 701,
        name: "fs-square-compact-test",
        placement: "sidebar_left",
        widget_type: "fs_square_compact"
      },
      overrides
    )
  end

  defp order(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ord-bull-sq",
        "side" => "buy",
        "filled" => true,
        "status_text" => "ORDER FILLED",
        "token_symbol" => "BULL",
        "sol_amount_ui" => 0.05,
        "payout_ui" => 635.13,
        "profit_ui" => 60.85,
        "profit_pct" => 10.0,
        "profit_usd" => 0.43,
        "fill_chance_pct" => 39.52,
        "settled_at" => System.system_time(:second) - 60
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&FsSquareCompact.fs_square_compact/1, assigns)

  test "renders root with fs_square_compact widget_type + FsHeroWidget hook" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ ~s(data-widget-type="fs_square_compact")
    assert html =~ ~s(phx-hook="FsHeroWidget")
  end

  test "constrained to 200 × 200 dimensions" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "w-[200px]"
    assert html =~ "h-[200px]"
  end

  test "brand header shows FateSwap + Solana DEX + LIVE" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "fateswap.io/images/logo-full.svg"
    assert html =~ "Solana&nbsp;DEX"
    assert html =~ "LIVE"
  end

  test "empty state renders shimmer skeleton when no trades" do
    html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

    assert html =~ "bw-skeleton"
    assert html =~ "fs-square-skeleton"
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
    refute html =~ "fs-square-skeleton"
  end

  test "renders token name + Received/Paid + positive PnL when order present" do
    html =
      render_widget(%{
        banner: banner(),
        trades: [order()],
        selection: "ord-bull-sq",
        order_override: nil
      })

    assert html =~ "BULL"
    assert html =~ "Received"
    assert html =~ "Paid"
    assert html =~ "635.13"
    assert html =~ "0.0500"
    assert html =~ "+10.00%"
    assert html =~ "▲"
  end

  test "click attributes carry banner + order id" do
    html =
      render_widget(%{
        banner: banner(%{id: 88}),
        trades: [order()],
        selection: "ord-bull-sq",
        order_override: nil
      })

    assert html =~ ~s(data-banner-id="88")
    assert html =~ ~s(data-order-id="ord-bull-sq")
    assert html =~ ~s(phx-click="widget_click")
    assert html =~ ~s(phx-value-subject="ord-bull-sq")
  end

  test "NOT FILLED order renders red PnL arrow" do
    nf =
      order(%{
        "filled" => false,
        "status_text" => "NOT FILLED",
        "profit_ui" => -0.005,
        "profit_pct" => -10.0
      })

    html = render_widget(%{banner: banner(), trades: [nf], selection: nil, order_override: nil})

    assert html =~ "▼"
    assert html =~ "text-[#EF4444]"
  end

  test "conviction marker rendered with left position" do
    html =
      render_widget(%{
        banner: banner(),
        trades: [order()],
        selection: nil,
        order_override: nil
      })

    assert html =~ ~r/left:\d+(\.\d+)?%/
  end
end
