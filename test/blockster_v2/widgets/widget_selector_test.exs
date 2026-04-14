defmodule BlocksterV2.Widgets.WidgetSelectorTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Widgets.WidgetSelector

  # ── Fixtures ──────────────────────────────────────────────────────────────

  defp bot(overrides \\ %{}) do
    base = %{
      "bot_id" => "kronos",
      "slug" => "kronos",
      "name" => "Kronos",
      "lp_price" => 1.23,
      "lp_price_change_1h_pct" => 0.5,
      "lp_price_change_6h_pct" => 1.0,
      "lp_price_change_24h_pct" => 2.0,
      "lp_price_change_48h_pct" => -0.5,
      "lp_price_change_7d_pct" => 4.0,
      "sol_balance" => 10.0,
      "rank" => 3
    }

    Map.merge(base, overrides)
  end

  defp trade(overrides) do
    base = %{
      "id" => "order-1",
      "side" => "buy",
      "status_text" => "DISCOUNT FILLED",
      "filled" => true,
      "profit_lamports" => 100_000,
      "discount_pct" => 5.0,
      "settled_at" => 1_700_000_000
    }

    Map.merge(base, overrides)
  end

  # ── RogueTrader ───────────────────────────────────────────────────────────

  describe "pick_rt biggest_gainer (default)" do
    test "picks (bot, tf) with largest positive change" do
      bots = [
        bot(%{"slug" => "a", "lp_price_change_7d_pct" => 4.0, "lp_price_change_24h_pct" => 1.0}),
        bot(%{"slug" => "b", "lp_price_change_1h_pct" => 8.5, "lp_price_change_24h_pct" => 1.0})
      ]

      assert WidgetSelector.pick_rt(bots, %{}) == {"b", "1h"}
    end

    test "returns nil when no numeric change values" do
      bots = [bot(%{"lp_price_change_1h_pct" => nil, "lp_price_change_6h_pct" => nil,
                   "lp_price_change_24h_pct" => nil, "lp_price_change_48h_pct" => nil,
                   "lp_price_change_7d_pct" => nil})]

      assert WidgetSelector.pick_rt(bots, %{}) == nil
    end

    test "empty bots list returns nil" do
      assert WidgetSelector.pick_rt([], %{}) == nil
    end
  end

  describe "pick_rt biggest_mover" do
    test "ranks by absolute change (negative can win)" do
      bots = [
        bot(%{"slug" => "a", "lp_price_change_7d_pct" => 4.0}),
        bot(%{"slug" => "b", "lp_price_change_7d_pct" => -9.0,
              "lp_price_change_1h_pct" => 0.1, "lp_price_change_6h_pct" => 0.1,
              "lp_price_change_24h_pct" => 0.1, "lp_price_change_48h_pct" => 0.1})
      ]

      assert WidgetSelector.pick_rt(bots, %{"selection" => "biggest_mover"}) == {"b", "7d"}
    end
  end

  describe "pick_rt highest_aum" do
    test "picks bot with largest sol_balance" do
      bots = [
        bot(%{"slug" => "a", "sol_balance" => 5.0}),
        bot(%{"slug" => "b", "sol_balance" => 50.0}),
        bot(%{"slug" => "c", "sol_balance" => 10.0})
      ]

      assert {"b", _tf} = WidgetSelector.pick_rt(bots, %{"selection" => "highest_aum"})
    end

    test "defaults timeframe to 7d" do
      bots = [bot()]
      assert {_, "7d"} = WidgetSelector.pick_rt(bots, %{"selection" => "highest_aum"})
    end
  end

  describe "pick_rt top_ranked" do
    test "picks bot with rank=1" do
      bots = [
        bot(%{"slug" => "a", "rank" => 3}),
        bot(%{"slug" => "b", "rank" => 1}),
        bot(%{"slug" => "c", "rank" => 2})
      ]

      assert {"b", "24h"} = WidgetSelector.pick_rt(bots, %{"selection" => "top_ranked"})
    end

    test "defaults timeframe to 24h" do
      bots = [bot(%{"rank" => 1})]
      assert {_, "24h"} = WidgetSelector.pick_rt(bots, %{"selection" => "top_ranked"})
    end
  end

  describe "pick_rt fixed" do
    test "pins to configured bot_id + timeframe" do
      config = %{"selection" => "fixed", "bot_id" => "pinned", "timeframe" => "48h"}
      assert WidgetSelector.pick_rt([], config) == {"pinned", "48h"}
    end

    test "defaults timeframe to 7d when missing" do
      config = %{"selection" => "fixed", "bot_id" => "pinned"}
      assert WidgetSelector.pick_rt([], config) == {"pinned", "7d"}
    end

    test "rejects fixed without bot_id" do
      assert WidgetSelector.pick_rt([], %{"selection" => "fixed"}) == nil
    end
  end

  describe "pick_rt unknown mode" do
    test "returns nil" do
      assert WidgetSelector.pick_rt([bot()], %{"selection" => "not_a_mode"}) == nil
    end
  end

  # ── FateSwap ──────────────────────────────────────────────────────────────

  describe "pick_fs biggest_profit (default)" do
    test "picks order with largest profit_lamports among settled+filled" do
      trades = [
        trade(%{"id" => "a", "profit_lamports" => 100}),
        trade(%{"id" => "b", "profit_lamports" => 9_000}),
        trade(%{"id" => "c", "profit_lamports" => 500})
      ]

      assert WidgetSelector.pick_fs(trades, %{}) == "b"
    end

    test "ignores unsettled orders" do
      trades = [
        trade(%{"id" => "a", "settled_at" => nil, "profit_lamports" => 100_000}),
        trade(%{"id" => "b", "profit_lamports" => 500})
      ]

      assert WidgetSelector.pick_fs(trades, %{}) == "b"
    end

    test "ignores unfilled orders" do
      trades = [
        trade(%{"id" => "a", "filled" => false, "status_text" => "NOT FILLED", "profit_lamports" => 100_000}),
        trade(%{"id" => "b", "profit_lamports" => 500})
      ]

      assert WidgetSelector.pick_fs(trades, %{}) == "b"
    end

    test "empty trades returns nil" do
      assert WidgetSelector.pick_fs([], %{}) == nil
    end
  end

  describe "pick_fs biggest_discount" do
    test "picks largest positive discount_pct" do
      trades = [
        trade(%{"id" => "a", "discount_pct" => 2.5}),
        trade(%{"id" => "b", "discount_pct" => 12.0}),
        trade(%{"id" => "c", "discount_pct" => -5.0})
      ]

      assert WidgetSelector.pick_fs(trades, %{"selection" => "biggest_discount"}) == "b"
    end
  end

  describe "pick_fs most_recent_filled" do
    test "picks newest settled_at" do
      trades = [
        trade(%{"id" => "a", "settled_at" => 100}),
        trade(%{"id" => "b", "settled_at" => 500}),
        trade(%{"id" => "c", "settled_at" => 300})
      ]

      assert WidgetSelector.pick_fs(trades, %{"selection" => "most_recent_filled"}) == "b"
    end
  end

  describe "pick_fs random_recent" do
    test "returns an id from the pool" do
      trades =
        for i <- 1..5, do: trade(%{"id" => "order-#{i}"})

      result = WidgetSelector.pick_fs(trades, %{"selection" => "random_recent"})
      assert is_binary(result)
      assert String.starts_with?(result, "order-")
    end

    test "empty pool returns nil" do
      assert WidgetSelector.pick_fs([], %{"selection" => "random_recent"}) == nil
    end
  end

  describe "pick_fs fixed" do
    test "pins to configured order_id" do
      assert WidgetSelector.pick_fs([], %{"selection" => "fixed", "order_id" => "pinned-id"}) ==
               "pinned-id"
    end

    test "rejects fixed without order_id" do
      assert WidgetSelector.pick_fs([], %{"selection" => "fixed"}) == nil
    end
  end

  # ── Banner-shape overload ─────────────────────────────────────────────────

  describe "pick_rt/pick_fs accept Banner structs" do
    test "Banner with widget_config is used as config source" do
      banner = %BlocksterV2.Ads.Banner{widget_config: %{"selection" => "biggest_gainer"}}
      bots = [bot(%{"slug" => "only", "lp_price_change_7d_pct" => 1.0})]
      assert {"only", _} = WidgetSelector.pick_rt(bots, banner)
    end

    test "Banner with selection=fixed on FS side" do
      banner = %BlocksterV2.Ads.Banner{
        widget_config: %{"selection" => "fixed", "order_id" => "pinned"}
      }

      assert WidgetSelector.pick_fs([], banner) == "pinned"
    end
  end

  describe "partition_banners" do
    test "separates banners by widget family" do
      banners = [
        %BlocksterV2.Ads.Banner{id: 1, widget_type: "rt_skyscraper"},
        %BlocksterV2.Ads.Banner{id: 2, widget_type: "fs_hero_portrait"},
        %BlocksterV2.Ads.Banner{id: 3, widget_type: nil},
        %BlocksterV2.Ads.Banner{id: 4, widget_type: "rt_chart_landscape"}
      ]

      %{rt: rt, fs: fs} = WidgetSelector.partition_banners(banners)
      assert length(rt) == 2
      assert length(fs) == 1
    end
  end
end
