defmodule BlocksterV2Web.Widgets.FsHeroPortraitTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsHeroPortrait

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 601,
      name: "fs-hero-portrait-test",
      placement: "article_inline_2",
      widget_type: "fs_hero_portrait"
    }, overrides)
  end

  defp order(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ord-bull-9",
        "side" => "buy",
        "filled" => true,
        "status_text" => "DISCOUNT FILLED",
        "token_symbol" => "BULL",
        "sol_amount_ui" => 0.05,
        "payout_ui" => 669.36,
        "payout_usd" => 4.72,
        "sol_usd" => 4.29,
        "multiplier" => 1.10,
        "discount_pct" => 9.1,
        "profit_ui" => 60.85,
        "profit_usd" => 0.43,
        "profit_pct" => 10.0,
        "fill_chance_pct" => 39.52,
        "tx_signature" => "5k3ZHxaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaav95Rz6",
        "wallet_truncated" => "7xQk…3mPa",
        "settled_at" => System.system_time(:second) - 120
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&FsHeroPortrait.fs_hero_portrait/1, assigns)

  describe "skeleton" do
    test "root carries banner id, hook, widget shell, order-id subject" do
      html = render_widget(%{banner: banner(%{id: 31}), trades: [], selection: nil, order_override: nil})

      assert html =~ ~s(data-banner-id="31")
      assert html =~ ~s(phx-hook="FsHeroWidget")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
      assert html =~ ~s(data-widget-type="fs_hero_portrait")
    end

    test "renders brand + Solana DEX + LIVE" do
      html = render_widget(%{banner: banner(), trades: [order(%{})], selection: nil, order_override: nil})

      assert html =~ "fateswap.io/images/logo-full.svg"
      assert html =~ "Solana&nbsp;DEX"
      assert html =~ "LIVE"
      assert html =~ "Gamble for a better price than market"
    end

    test "empty state renders shimmer skeleton when no trades" do
      html = render_widget(%{banner: banner(), trades: [], selection: nil, order_override: nil})

      assert html =~ "bw-skeleton"
      assert html =~ "fs-hero-skeleton"
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
      refute html =~ "fs-hero-skeleton"
    end
  end

  describe "order card — buy variant" do
    setup do
      %{
        html:
          render_widget(%{
            banner: banner(),
            trades: [order(%{})],
            selection: "ord-bull-9",
            order_override: nil
          })
      }
    end

    test "status pill shows DISCOUNT FILLED in green", %{html: html} do
      assert html =~ "DISCOUNT FILLED"
      assert html =~ "text-[#22C55E]"
    end

    test "headline uses Bought + token qty + BULL with third-person copy", %{html: html} do
      assert html =~ "Bought"
      assert html =~ "669.36"
      assert html =~ "BULL"
      assert html =~ "9.10%"
      assert html =~ "discount"
    end

    test "third-person Trader Received + Trader Paid labels (NOT 'You')", %{html: html} do
      assert html =~ "Trader Received"
      assert html =~ "Trader Paid"
      refute html =~ "You received"
      refute html =~ "You paid"
      refute html =~ "YOU RECEIVED"
    end

    test "profit row shows positive profit with +sign + pct", %{html: html} do
      assert html =~ "+60.85"
      assert html =~ "(+10.00%)"
      # Profit USD
      assert html =~ "$0.43"
    end

    test "Swap complete badge appears for filled orders", %{html: html} do
      assert html =~ "Swap complete"
    end

    test "meta footer shows fill chance + TX hash (no Roll number)", %{html: html} do
      assert html =~ "Fill chance:"
      assert html =~ "39.52%"
      assert html =~ "TX:"
      refute html =~ "Roll"
    end
  end

  describe "NOT FILLED variant" do
    test "shows NOT FILLED pill, red profit color, no Swap Complete badge" do
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
      refute html =~ "Swap complete"
    end
  end

  describe "sell variant" do
    test "uses Sold verb + premium instead of discount + Trader Sold label" do
      sell =
        order(%{
          "id" => "ord-sell",
          "side" => "sell",
          "status_text" => "ORDER FILLED",
          "discount_pct" => 10.0,
          "payout_ui" => 0.0593
        })

      html = render_widget(%{banner: banner(), trades: [sell], selection: nil, order_override: nil})

      assert html =~ "Sold"
      assert html =~ "premium"
      assert html =~ "Trader Sold"
      assert html =~ "ORDER FILLED"
    end
  end
end
