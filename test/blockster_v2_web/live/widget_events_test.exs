defmodule BlocksterV2Web.WidgetEventsTest do
  use BlocksterV2Web.LiveCase, async: false

  import BlocksterV2.Widgets.MnesiaCase, only: [setup_widget_mnesia: 1]
  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads
  alias BlocksterV2Web.WidgetEventsTestHost

  setup :setup_widget_mnesia

  defp create_widget_banner(attrs \\ %{}) do
    base = %{
      name: "fs-hero-#{:erlang.unique_integer([:positive, :monotonic])}",
      placement: "sidebar_right",
      widget_type: "fs_hero_portrait",
      widget_config: %{"selection" => "biggest_profit"}
    }

    {:ok, banner} = Ads.create_banner(Map.merge(base, attrs))
    banner
  end

  describe "mount_widgets/2" do
    test "subscribes to fs + rt data topics + per-banner selection topics on connected mount",
         %{conn: conn} do
      b1 = create_widget_banner(%{name: "b1", widget_type: "fs_hero_portrait"})
      b2 = create_widget_banner(%{name: "b2", widget_type: "rt_chart_landscape"})

      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      # Dispatch a message on each topic the macro should have subscribed to.
      # If the subscription happened, the LV receives it and push_event fires.
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "widgets:fateswap:feed", {:fs_trades, [%{"id" => "t1"}]})
      assert_push_event(view, "widget:fs_feed:update", %{trades: [%{"id" => "t1"}]})

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "widgets:roguetrader:bots", {:rt_bots, [%{"bot_id" => "x"}]})
      assert_push_event(view, "widget:rt_bots:update", %{bots: [%{"bot_id" => "x"}]})

      b1_topic = "widgets:selection:#{b1.id}"
      b2_topic = "widgets:selection:#{b2.id}"
      b1_event = "widget:#{b1.id}:select"
      b2_event = "widget:#{b2.id}:select"

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, b1_topic, {:selection_changed, b1.id, "order-1"})
      assert_push_event(view, ^b1_event, %{order_id: "order-1"})

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, b2_topic, {:selection_changed, b2.id, {"kronos", "7d"}})
      assert_push_event(view, ^b2_event, %{bot_id: "kronos", tf: "7d"})
    end

    test "increments impressions exactly once per banner on connected mount", %{conn: conn} do
      b1 = create_widget_banner(%{name: "imp1"})
      b2 = create_widget_banner(%{name: "imp2"})

      assert Ads.get_banner!(b1.id).impressions == 0
      assert Ads.get_banner!(b2.id).impressions == 0

      {:ok, _view, _html} = live_isolated(conn, WidgetEventsTestHost)

      # Connected mount fires once per banner. The disconnected HTTP render
      # does not increment because the macro gates on `connected?/1`.
      assert Ads.get_banner!(b1.id).impressions == 1
      assert Ads.get_banner!(b2.id).impressions == 1
    end

    test "does not subscribe or increment for banners with nil widget_type", %{conn: conn} do
      {:ok, plain} =
        Ads.create_banner(%{
          name: "plain",
          placement: "sidebar_right",
          image_url: "https://example.com/plain.png"
        })

      {:ok, _view, _html} = live_isolated(conn, WidgetEventsTestHost)

      # A selection broadcast on the plain banner's topic would cause
      # `handle_info/2` to fire only if the LV subscribed, which
      # `mount_widgets/2` must skip for banners without a `widget_type`.
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "widgets:selection:#{plain.id}",
        {:selection_changed, plain.id, "would-never-arrive"}
      )

      # Impressions stays 0 because the plain banner isn't a widget.
      assert Ads.get_banner!(plain.id).impressions == 0
    end
  end

  describe "handle_info/2" do
    test "{:fs_trades, _} updates @fs_trades and pushes widget:fs_feed:update", %{conn: conn} do
      _ = create_widget_banner()
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "widgets:fateswap:feed",
        {:fs_trades, [%{"id" => "a"}, %{"id" => "b"}]}
      )

      assert_push_event(view, "widget:fs_feed:update", %{trades: trades})
      assert length(trades) == 2
    end

    test "{:rt_bots, _} updates @rt_bots and pushes widget:rt_bots:update", %{conn: conn} do
      _ = create_widget_banner()
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "widgets:roguetrader:bots",
        {:rt_bots, [%{"bot_id" => "kronos"}]}
      )

      assert_push_event(view, "widget:rt_bots:update", %{bots: [%{"bot_id" => "kronos"}]})
    end

    test "{:selection_changed, banner_id, {bot_id, tf}} pushes select payload with chart points",
         %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "rt_chart_landscape"})

      # Seed a chart row the macro can pick up via RogueTraderChartTracker.get_series/2
      points = [%{time: 1, value: 10.0}, %{time: 2, value: 11.0}]

      :mnesia.dirty_write(
        {:widget_rt_chart_cache, {"kronos", "7d"}, "kronos", "7d", points, 11.0, 10.0, 0.1,
         System.system_time(:second)}
      )

      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      topic = "widgets:selection:#{banner.id}"
      event = "widget:#{banner.id}:select"

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, topic, {:selection_changed, banner.id, {"kronos", "7d"}})

      assert_push_event(view, ^event, %{bot_id: "kronos", tf: "7d", points: ^points})
    end

    test "{:selection_changed, banner_id, order_id} pushes select payload with order", %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "fs_hero_landscape"})
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      topic = "widgets:selection:#{banner.id}"
      event = "widget:#{banner.id}:select"

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, topic, {:selection_changed, banner.id, "order-xyz"})

      assert_push_event(view, ^event, %{order_id: "order-xyz"})
    end

    test "{:selection_changed, _, nil} is a no-op — LV stays alive", %{conn: conn} do
      banner = create_widget_banner()
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      topic = "widgets:selection:#{banner.id}"
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, topic, {:selection_changed, banner.id, nil})

      # If the nil path crashed the LV, the next subscribed message wouldn't
      # round-trip. Broadcast a known event and assert we still see the push.
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "widgets:fateswap:feed", {:fs_trades, []})
      assert_push_event(view, "widget:fs_feed:update", %{trades: []})
    end
  end

  describe "handle_event(\"widget_click\", ...)" do
    test "tuple subject (from DOM JSON map) → increments clicks and redirects to /bot/:id",
         %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "rt_chart_landscape"})
      assert Ads.get_banner!(banner.id).clicks == 0

      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      assert {:error, {:redirect, %{to: url}}} =
               render_hook(view, "widget_click", %{
                 "banner_id" => Integer.to_string(banner.id),
                 "subject" => %{"bot_id" => "kronos", "tf" => "7d"}
               })

      assert url == "https://roguetrader.io/bot/kronos"
      assert Ads.get_banner!(banner.id).clicks == 1
    end

    test "binary order_id subject → redirects to /orders/:id", %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "fs_hero_portrait"})
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      assert {:error, {:redirect, %{to: url}}} =
               render_hook(view, "widget_click", %{
                 "banner_id" => Integer.to_string(banner.id),
                 "subject" => "order-abc"
               })

      assert url == "https://fateswap.io/orders/order-abc"
      assert Ads.get_banner!(banner.id).clicks == 1
    end

    test "subject \"rt\" → redirects to RogueTrader homepage", %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "rt_skyscraper"})
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      assert {:error, {:redirect, %{to: url}}} =
               render_hook(view, "widget_click", %{
                 "banner_id" => Integer.to_string(banner.id),
                 "subject" => "rt"
               })

      assert url == "https://roguetrader.io"
    end

    test "subject \"fs\" → redirects to FateSwap homepage", %{conn: conn} do
      banner = create_widget_banner(%{widget_type: "fs_skyscraper"})
      {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

      assert {:error, {:redirect, %{to: url}}} =
               render_hook(view, "widget_click", %{
                 "banner_id" => Integer.to_string(banner.id),
                 "subject" => "fs"
               })

      assert url == "https://fateswap.io"
    end
  end

  # Phase 6e — sweep every shipped widget_type for impression + click behaviour.
  # Each case is a 3-tuple: {widget_type, click_subject, expected_redirect_url}.
  # "rt_bot_tuple" / "fs_order_id" signal structured subjects resolved per-test.
  @widget_click_cases [
    {"rt_skyscraper", "rt", "https://roguetrader.io"},
    {"rt_ticker", "rt", "https://roguetrader.io"},
    {"rt_leaderboard_inline", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"rt_chart_landscape", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"rt_chart_portrait", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"rt_full_card", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"rt_square_compact", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"rt_sidebar_tile", :rt_bot_tuple, "https://roguetrader.io/bot/kronos"},
    {"fs_skyscraper", "fs", "https://fateswap.io"},
    {"fs_ticker", "fs", "https://fateswap.io"},
    {"fs_hero_portrait", :fs_order_id, "https://fateswap.io/orders/ord-sweep"},
    {"fs_hero_landscape", :fs_order_id, "https://fateswap.io/orders/ord-sweep"},
    {"fs_square_compact", :fs_order_id, "https://fateswap.io/orders/ord-sweep"},
    {"fs_sidebar_tile", :fs_order_id, "https://fateswap.io/orders/ord-sweep"}
  ]

  describe "impression + click sweep — every shipped widget_type" do
    for {widget_type, subject_kind, expected_url} <- @widget_click_cases do
      @tag widget_type: widget_type, subject_kind: subject_kind, expected_url: expected_url
      test "#{widget_type}: mount increments impressions, widget_click increments clicks + redirects", %{
        conn: conn,
        widget_type: widget_type,
        subject_kind: subject_kind,
        expected_url: expected_url
      } do
        {:ok, banner} =
          Ads.create_banner(%{
            name: "sweep-#{widget_type}",
            placement: placement_for(widget_type),
            widget_type: widget_type,
            widget_config: default_widget_config(widget_type)
          })

        assert Ads.get_banner!(banner.id).impressions == 0
        assert Ads.get_banner!(banner.id).clicks == 0

        {:ok, view, _html} = live_isolated(conn, WidgetEventsTestHost)

        # Connected mount fires the impression for every widget banner.
        assert Ads.get_banner!(banner.id).impressions == 1

        subject = subject_payload(subject_kind)

        assert {:error, {:redirect, %{to: url}}} =
                 render_hook(view, "widget_click", %{
                   "banner_id" => Integer.to_string(banner.id),
                   "subject" => subject
                 })

        assert url == expected_url, "#{widget_type}: expected redirect to #{expected_url}, got #{url}"
        assert Ads.get_banner!(banner.id).clicks == 1
      end
    end
  end

  defp subject_payload(:rt_bot_tuple), do: %{"bot_id" => "kronos", "tf" => "7d"}
  defp subject_payload(:fs_order_id), do: "ord-sweep"
  defp subject_payload(bin) when is_binary(bin), do: bin

  defp default_widget_config(t)
       when t in ~w(rt_chart_landscape rt_chart_portrait rt_full_card rt_square_compact rt_sidebar_tile),
       do: %{"selection" => "biggest_gainer"}

  defp default_widget_config(t)
       when t in ~w(fs_hero_portrait fs_hero_landscape fs_square_compact fs_sidebar_tile),
       do: %{"selection" => "biggest_profit"}

  defp default_widget_config(_), do: %{}

  defp placement_for("rt_ticker"), do: "homepage_top_desktop"
  defp placement_for("fs_ticker"), do: "homepage_top_mobile"
  defp placement_for("rt_leaderboard_inline"), do: "homepage_inline_desktop"
  defp placement_for(t) when t in ~w(rt_chart_landscape rt_chart_portrait rt_full_card), do: "article_inline_1"
  defp placement_for(t) when t in ~w(fs_hero_portrait fs_hero_landscape), do: "article_inline_2"
  defp placement_for(_), do: "sidebar_right"
end
