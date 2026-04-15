defmodule BlocksterV2Web.Widgets.FsSkyscraperTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsSkyscraper

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 101,
      name: "fs-test",
      placement: "sidebar_left",
      widget_type: "fs_skyscraper"
    }, overrides)
  end

  defp trade(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "order-1",
        "side" => "buy",
        "status_text" => "DISCOUNT FILLED",
        "filled" => true,
        "token_symbol" => "BULL",
        "token_logo_url" => "https://example.com/bull.png",
        "sol_amount_ui" => 0.05,
        "payout_ui" => 0.0669,
        "multiplier" => 1.10,
        "discount_pct" => 9.1,
        "profit_ui" => 0.0169,
        "profit_usd" => 2.71,
        "wallet_truncated" => "7xQk…3mPa",
        "settled_at" => System.system_time(:second) - 120
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&FsSkyscraper.fs_skyscraper/1, assigns)
  end

  describe "skeleton" do
    test "renders root with data-banner-id, hook, widget click subject" do
      html = render_widget(%{banner: banner(%{id: 7}), trades: []})

      assert html =~ ~s(data-banner-id="7")
      assert html =~ ~s(phx-hook="FsSkyscraperWidget")
      assert html =~ ~s(phx-click="widget_click")
      assert html =~ ~s(phx-value-subject="fs")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
    end

    test "renders header: FateSwap logo, SOLANA DEX label, brand-gradient tagline, LIVE pill" do
      html = render_widget(%{banner: banner(), trades: []})

      assert html =~ "fateswap.io/images/logo-full.svg"
      assert html =~ "Solana&nbsp;DEX"
      assert html =~ "Gamble for a better price than market"
      assert html =~ "LIVE"
    end

    test "renders shimmer skeleton when trades is []" do
      html = render_widget(%{banner: banner(), trades: []})

      assert html =~ "bw-skeleton"
      assert html =~ "fs-skyscraper-skeleton"
    end

    test "renders tracker error placeholder when trades is [] and tracker_error? is true" do
      html = render_widget(%{banner: banner(), trades: [], tracker_error?: true})

      assert html =~ "FateSwap feed paused"
      refute html =~ "fs-skyscraper-skeleton"
    end

    test "renders footer with Open FateSwap link text" do
      html = render_widget(%{banner: banner(), trades: []})

      assert html =~ "Open FateSwap"
    end
  end

  describe "trade rows" do
    test "renders a buy + DISCOUNT FILLED trade with third-person data attrs" do
      t = trade()
      html = render_widget(%{banner: banner(), trades: [t]})

      assert html =~ ~s(data-trade-id="order-1")
      assert html =~ "BUY BULL"
      assert html =~ "DISCOUNT FILLED"
      assert html =~ "0.0500"
      assert html =~ "0.0669"
      assert html =~ "Discount"
      assert html =~ "×1.10"
      assert html =~ "+0.02 SOL"
      # Third-person footer copy (NOT 'You received' / 'You paid')
      assert html =~ "Trader Received"
      refute html =~ "You received"
      refute html =~ "You Paid"
    end

    test "renders a sell + NOT FILLED trade with red styling and loss sign" do
      t =
        trade(%{
          "id" => "order-2",
          "side" => "sell",
          "status_text" => "NOT FILLED",
          "filled" => false,
          "token_symbol" => "WIF",
          "profit_ui" => -1.2,
          "profit_usd" => -192.4,
          "discount_pct" => 10.0
        })

      html = render_widget(%{banner: banner(), trades: [t]})

      assert html =~ "SELL WIF"
      assert html =~ "NOT FILLED"
      assert html =~ "Premium"
      assert html =~ "−1.20 SOL"
      assert html =~ "text-[#f87171]"
    end

    test "caps visible rows at 20 even if more trades are passed" do
      trades =
        for i <- 1..30 do
          trade(%{"id" => "order-#{i}"})
        end

      html = render_widget(%{banner: banner(), trades: trades})

      # First 20 should render
      assert html =~ ~s(data-trade-id="order-1")
      assert html =~ ~s(data-trade-id="order-20")
      # Beyond cap should not
      refute html =~ ~s(data-trade-id="order-21")
      refute html =~ ~s(data-trade-id="order-30")
    end
  end

  describe "resilience" do
    test "handles missing token_logo_url without crashing" do
      html = render_widget(%{banner: banner(), trades: [trade(%{"token_logo_url" => nil})]})

      refute html =~ "https://example.com/bull.png"
      assert html =~ "BUY BULL"
    end

    test "handles missing discount_pct / multiplier gracefully" do
      t = trade(%{"discount_pct" => nil, "multiplier" => nil})
      html = render_widget(%{banner: banner(), trades: [t]})

      assert html =~ "BUY BULL"
      # em dash fallback for missing discount
      assert html =~ "—"
    end
  end
end
