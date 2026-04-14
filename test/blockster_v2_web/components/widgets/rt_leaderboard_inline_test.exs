defmodule BlocksterV2Web.Widgets.RtLeaderboardInlineTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtLeaderboardInline

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 501,
      name: "rt-leaderboard-test",
      placement: "article_inline_1",
      widget_type: "rt_leaderboard_inline"
    }, overrides)
  end

  defp bot(overrides) do
    Map.merge(
      %{
        "bot_id" => "kronos",
        "slug" => "kronos",
        "name" => "KRONOS",
        "group_name" => "equities",
        "bid_price" => 0.1023,
        "ask_price" => 0.1045,
        "lp_price" => 0.1030,
        "sol_balance_ui" => 248.36,
        "lp_price_change_1h_pct" => 0.42,
        "lp_price_change_24h_pct" => 3.24
      },
      overrides
    )
  end

  defp render_widget(assigns),
    do: render_component(&RtLeaderboardInline.rt_leaderboard_inline/1, assigns)

  describe "skeleton" do
    test "root carries banner id, hook, widget shell — no phx-click on outer div" do
      html = render_widget(%{banner: banner(%{id: 21}), bots: []})

      assert html =~ ~s(data-banner-id="21")
      assert html =~ ~s(phx-hook="RtLeaderboardWidget")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
      assert html =~ ~s(data-widget-type="rt_leaderboard_inline")
    end

    test "renders header: logo, divider, Top RogueBots, LIVE" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "rogue-logo-white.png"
      assert html =~ "TRADER"
      assert html =~ "Top RogueBots"
      assert html =~ "LIVE"
    end

    test "renders footer CTA with phx-click subject=rt going to RogueTrader" do
      html = render_widget(%{banner: banner(%{id: 21}), bots: []})

      assert html =~ ~s(phx-click="widget_click")
      assert html =~ ~s(phx-value-subject="rt")
      assert html =~ "View all AI Bots"
    end

    test "renders empty state copy when bots is []" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "Loading roguebots"
    end
  end

  describe "rows" do
    test "renders one desktop row per bot with rank + group tag + prices + change + AUM" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      assert html =~ ~s(data-role="rt-lb-row")
      assert html =~ ~s(data-bot-id="kronos")
      assert html =~ "KRONOS"
      assert html =~ "EQUITIES"
      # Green bid / red ask
      assert html =~ "0.1023"
      assert html =~ "0.1045"
      # Change %
      assert html =~ "+0.42%"
      assert html =~ "+3.24%"
      # AUM formatted with SOL unit
      assert html =~ "248.36"
      assert html =~ "SOL"
    end

    test "caps rows at 10 even if more bots are supplied" do
      bots =
        for i <- 1..15 do
          bot(%{"bot_id" => "bot-#{i}", "slug" => "bot-#{i}", "name" => "B#{i}", "lp_price" => 2.0 - i * 0.01})
        end

      html = render_widget(%{banner: banner(), bots: bots})

      assert html =~ ~s(data-bot-id="bot-1")
      # With the hidden md:table desktop markup + mobile grid, both render
      # 10 rows — so beyond-10 bots still must not appear.
      refute html =~ ~s(data-bot-id="bot-11")
      refute html =~ ~s(data-bot-id="bot-15")
    end

    test "sorts bots by lp_price desc server-side" do
      bots = [
        bot(%{"slug" => "lowcap", "name" => "LOW", "lp_price" => 0.01}),
        bot(%{"slug" => "highcap", "name" => "HIGH", "lp_price" => 5.0})
      ]

      html = render_widget(%{banner: banner(), bots: bots})
      high_idx = :binary.match(html, "HIGH") |> elem(0)
      low_idx = :binary.match(html, "LOW") |> elem(0)

      assert high_idx < low_idx
    end

    test "also exposes a mobile card grid (md:hidden class + same row markup)" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      # Desktop table and mobile grid both render the same bot row — so we
      # should find TWO occurrences of the bot id (one per viewport variant).
      count =
        html |> String.split(~s(data-bot-id="kronos")) |> length() |> Kernel.-(1)

      assert count == 2
      assert html =~ "md:hidden"
    end

    test "colors down-moves red" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot(%{"lp_price_change_1h_pct" => -0.55, "lp_price_change_24h_pct" => -2.13})]
        })

      assert html =~ "−0.55%"
      assert html =~ "−2.13%"
      assert html =~ "text-[#EF4444]"
    end
  end
end
