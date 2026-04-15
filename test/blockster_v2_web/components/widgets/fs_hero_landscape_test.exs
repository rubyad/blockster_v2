defmodule BlocksterV2Web.Widgets.FsHeroLandscapeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsHeroLandscape

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 701,
      name: "fs-hero-landscape-test",
      placement: "homepage_inline",
      widget_type: "fs_hero_landscape"
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
        "tx_signature" => "5k3ZHxaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaav95Rz6",
        "conviction_label" => "Conservative",
        "quote" => "Fate loves a bargain hunter.",
        "settled_at" => System.system_time(:second) - 120
      },
      overrides
    )
  end

  defp render_widget(assigns),
    do: render_component(&FsHeroLandscape.fs_hero_landscape/1, assigns)

  describe "skeleton" do
    test "root carries banner id, hook, widget shell" do
      html = render_widget(%{banner: banner(%{id: 41}), trades: [], selection: nil, order_override: nil})

      assert html =~ ~s(data-banner-id="41")
      assert html =~ ~s(phx-hook="FsHeroWidget")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
      assert html =~ ~s(data-widget-type="fs_hero_landscape")
    end

    test "header: logo, Solana DEX, LIVE pill, gradient tagline" do
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

  describe "order — buy variant" do
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

    test "big headline with Bought + qty + token", %{html: html} do
      assert html =~ "Bought"
      assert html =~ "669.36"
      assert html =~ "BULL"
      assert html =~ "9.10%"
      assert html =~ "discount"
    end

    test "2×2 grid uses third-person labels (Trader Received + Trader Paid)", %{html: html} do
      assert html =~ "Trader Received"
      assert html =~ "Trader Paid"
      assert html =~ "Profit"
      assert html =~ "Fill Chance"
      refute html =~ "You received"
      refute html =~ "You Paid"
    end

    test "profit cell shows +value + pct", %{html: html} do
      assert html =~ "+60.85"
      assert html =~ "(+10.00%)"
    end

    test "fill chance cell shows the numeric percentage", %{html: html} do
      assert html =~ "39.52"
    end

    test "conviction bar labeled + rainbow gradient + marker position", %{html: html} do
      assert html =~ "Conviction:"
      assert html =~ "Conservative"
      # Rainbow gradient (inline style)
      assert html =~ "linear-gradient(90deg,#22C55E 0%,#EAB308 50%,#EF4444 100%)"
      # Marker uses a left:<pct>% style — just make sure the style carries a
      # numeric left: offset (float precision differs across OTP versions).
      assert html =~ ~r/left:\d+(\.\d+)?%/
    end

    test "quote is rendered in italic", %{html: html} do
      assert html =~ "Fate loves a bargain hunter."
      assert html =~ "italic"
    end

    test "footer tagline + TX label", %{html: html} do
      assert html =~ "Memecoin trading on steroids."
      assert html =~ "TX:"
    end

    test "Swap Complete badge for filled order", %{html: html} do
      assert html =~ "Swap complete"
    end
  end

  describe "NOT FILLED variant" do
    test "renders red profit, NOT FILLED pill, no Swap Complete badge" do
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
end
