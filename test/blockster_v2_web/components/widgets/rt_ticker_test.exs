defmodule BlocksterV2Web.Widgets.RtTickerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtTicker

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 301,
      name: "rt-ticker-test",
      placement: "homepage_top_desktop",
      widget_type: "rt_ticker"
    }, overrides)
  end

  defp bot(overrides) do
    Map.merge(
      %{
        "bot_id" => "hermes",
        "slug" => "hermes",
        "name" => "HERMES",
        "group_name" => "crypto",
        "bid_price" => 0.1023,
        "ask_price" => 0.1045,
        "lp_price" => 0.1030,
        "lp_price_change_24h_pct" => 3.24
      },
      overrides
    )
  end

  defp render_widget(assigns), do: render_component(&RtTicker.rt_ticker/1, assigns)

  describe "skeleton" do
    test "root carries banner id, hook, widget-click subject, widget shell classes" do
      html = render_widget(%{banner: banner(%{id: 11}), bots: []})

      assert html =~ ~s(data-banner-id="11")
      assert html =~ ~s(phx-hook="RtTickerWidget")
      assert html =~ ~s(phx-click="widget_click")
      assert html =~ ~s(phx-value-subject="rt")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
      assert html =~ "bw-ticker"
      assert html =~ ~s(data-widget-type="rt_ticker")
    end

    test "renders brand lock-up: rogue logo, TRADER overlay, LIVE pill, CTA" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      assert html =~ "rogue-logo-white.png"
      assert html =~ "TRADER"
      assert html =~ "Live"
      assert html =~ "View all AI Bots"
    end

    test "renders empty state when bots is []" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "Loading prices"
      refute html =~ "bw-marquee-track"
    end
  end

  describe "ticker items" do
    test "renders one item per bot with bid/ask prices + change pill" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      assert html =~ ~s(data-bot-id="hermes")
      assert html =~ "HERMES"
      assert html =~ "0.1023"
      assert html =~ "0.1045"
      assert html =~ "+3.24%"
      assert html =~ "▲"
    end

    test "down-move shows red color + down arrow" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot(%{"lp_price_change_24h_pct" => -2.13, "name" => "BEAR"})]
        })

      assert html =~ "BEAR"
      assert html =~ "−2.13%"
      assert html =~ "▼"
      assert html =~ "text-[#EF4444]"
    end

    test "duplicates the item list for seamless loop" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      bot_occurrences =
        html
        |> String.split(~s(data-bot-id="hermes"))
        |> length()
        |> Kernel.-(1)

      assert bot_occurrences == 2
    end

    test "caps visible bots at 30" do
      bots =
        for i <- 1..45 do
          bot(%{"bot_id" => "bot-#{i}", "slug" => "bot-#{i}", "name" => "BOT#{i}", "lp_price" => 50.0 - i})
        end

      html = render_widget(%{banner: banner(), bots: bots})

      assert html =~ ~s(data-bot-id="bot-1")
      # Top-30 only: bot 31+ shouldn't appear.
      refute html =~ ~s(data-bot-id="bot-31")
      refute html =~ ~s(data-bot-id="bot-45")
    end

    test "sorts bots server-side by lp_price desc — does not trust upstream order" do
      bots = [
        bot(%{"slug" => "lowcap", "name" => "LOW", "lp_price" => 0.05}),
        bot(%{"slug" => "highcap", "name" => "HIGH", "lp_price" => 1.20})
      ]

      html = render_widget(%{banner: banner(), bots: bots})
      high_idx = :binary.match(html, "HIGH") |> elem(0)
      low_idx = :binary.match(html, "LOW") |> elem(0)

      assert high_idx < low_idx
    end
  end

  describe "group coloring" do
    test "picks the equities hex for group_name=equities" do
      html =
        render_widget(%{banner: banner(), bots: [bot(%{"group_name" => "equities"})]})

      assert html =~ "#10B981"
    end

    test "falls back to neutral hex when group is unknown" do
      html = render_widget(%{banner: banner(), bots: [bot(%{"group_name" => "???"})]})

      assert html =~ "#6B7280"
    end
  end
end
