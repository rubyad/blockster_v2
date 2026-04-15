defmodule BlocksterV2Web.Widgets.FsTickerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.FsTicker

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 401,
      name: "fs-ticker-test",
      placement: "homepage_top_desktop",
      widget_type: "fs_ticker"
    }, overrides)
  end

  defp trade(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "order-1",
        "side" => "buy",
        "filled" => true,
        "status_text" => "DISCOUNT FILLED",
        "token_symbol" => "BULL",
        "token_logo_url" => "https://example.com/bull.png",
        "sol_amount_ui" => 0.05,
        "payout_ui" => 669.36,
        "multiplier" => 1.10,
        "discount_pct" => 9.1,
        "profit_ui" => 60.85,
        "profit_usd" => 0.43,
        "wallet_truncated" => "7xQk…3mPa",
        "settled_at" => System.system_time(:second) - 120
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&FsTicker.fs_ticker/1, assigns)

  describe "skeleton" do
    test "root carries banner id, hook, widget-click subject=fs, widget shell" do
      html = render_widget(%{banner: banner(%{id: 12}), trades: []})

      assert html =~ ~s(data-banner-id="12")
      assert html =~ ~s(phx-hook="FsTickerWidget")
      assert html =~ ~s(phx-click="widget_click")
      assert html =~ ~s(phx-value-subject="fs")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
      assert html =~ "bw-ticker"
      assert html =~ ~s(data-widget-type="fs_ticker")
    end

    test "renders brand lock-up: FateSwap logo, Solana DEX label, LIVE pill, CTA" do
      html = render_widget(%{banner: banner(), trades: [trade(%{})]})

      assert html =~ "fateswap.io/images/logo-full.svg"
      assert html =~ "Solana&nbsp;DEX"
      assert html =~ "Live"
      assert html =~ "Open FateSwap"
    end

    test "renders shimmer skeleton when trades is []" do
      html = render_widget(%{banner: banner(), trades: []})

      assert html =~ "bw-skeleton"
      assert html =~ "fs-ticker-skeleton"
      refute html =~ "bw-marquee-track"
    end

    test "renders tracker error placeholder when trades is [] and tracker_error? is true" do
      html = render_widget(%{banner: banner(), trades: [], tracker_error?: true})

      assert html =~ "FateSwap feed paused"
      refute html =~ "fs-ticker-skeleton"
    end
  end

  describe "ticker items" do
    test "renders one item per trade with token symbol, amount, pnl pill, buy arrow" do
      html = render_widget(%{banner: banner(), trades: [trade(%{})]})

      assert html =~ ~s(data-trade-id="order-1")
      assert html =~ "BULL"
      # Amount rendered from payout_ui (669.36 → "669.36")
      assert html =~ "669.36"
      # Buy arrow
      assert html =~ "↗"
      # Profit pill — multiplier 1.10 → +10.0%
      assert html =~ "+10.0%"
      assert html =~ "▲"
    end

    test "sell trade renders the sell arrow + yellow chip" do
      html =
        render_widget(%{
          banner: banner(),
          trades: [trade(%{"id" => "order-sell", "side" => "sell", "token_symbol" => "WIF"})]
        })

      assert html =~ "↘"
      assert html =~ "WIF"
      assert html =~ "#EAB308"
    end

    test "NOT FILLED trade shows NOT FILLED label + red pill" do
      html =
        render_widget(%{
          banner: banner(),
          trades: [
            trade(%{"id" => "order-nf", "filled" => false, "status_text" => "NOT FILLED"})
          ]
        })

      assert html =~ "NOT FILLED"
      assert html =~ "▼"
      assert html =~ "text-[#EF4444]"
    end

    test "duplicates the item list for a seamless marquee loop" do
      html = render_widget(%{banner: banner(), trades: [trade(%{})]})

      count =
        html |> String.split(~s(data-trade-id="order-1")) |> length() |> Kernel.-(1)

      assert count == 2
    end

    test "caps visible trades at 20" do
      trades = for i <- 1..30, do: trade(%{"id" => "order-#{i}"})

      html = render_widget(%{banner: banner(), trades: trades})

      assert html =~ ~s(data-trade-id="order-1")
      assert html =~ ~s(data-trade-id="order-20")
      refute html =~ ~s(data-trade-id="order-21")
      refute html =~ ~s(data-trade-id="order-30")
    end
  end
end
