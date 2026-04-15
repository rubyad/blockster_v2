defmodule BlocksterV2Web.WidgetEvents do
  @moduledoc """
  Shared LiveView macro that wires real-time widgets into any page.

  `use BlocksterV2Web.WidgetEvents` adds:

    * `mount_widgets/2` — call from `mount/3` with the list of banners
      rendered on the page. On connected mount it subscribes to the
      shared data topics (`widgets:fateswap:feed`, `widgets:roguetrader:bots`)
      plus a per-banner selection topic, increments impressions once per
      banner, and seeds initial assigns from the local Mnesia caches so
      first paint is never empty.

    * `handle_info/2` clauses for `{:fs_trades, _}`, `{:rt_bots, _}`,
      `{:rt_chart, _, _, _}`, `{:selection_changed, _, _}`.

    * `handle_event("widget_click", _, _)` — normalises the subject that
      comes back from the DOM (map or binary), increments the click
      counter, and external-redirects via `ClickRouter.url_for/2`.

  Plan: docs/solana/realtime_widgets_plan.md · §E "LiveView integration".

  Phase 2a deviations honored here:
    * Trackers expose local Mnesia reads (`get_trades/0`, `get_bots/0`,
      `get_series/2`), so the seed call doesn't cross nodes.
    * `WidgetSelector` can return `nil` — macro handles that without
      pushing stale events or crashing.
    * `subject` payloads come back as JSON-decoded maps: a `{bot_id, tf}`
      tuple arrives as `%{"bot_id" => _, "tf" => _}`. The macro converts
      back to a tuple before handing off to `ClickRouter`.
  """

  defmacro __using__(_opts) do
    quote do
      alias BlocksterV2.Ads
      alias BlocksterV2.Widgets.{ClickRouter, FateSwapFeedTracker, RogueTraderBotsTracker, RogueTraderChartTracker, TrackerStatus}

      @widget_fs_feed_topic "widgets:fateswap:feed"
      @widget_rt_bots_topic "widgets:roguetrader:bots"
      @widget_selection_topic_prefix "widgets:selection:"
      @widget_rt_chart_topic_prefix "widgets:roguetrader:chart:"

      @doc """
      Seeds widget assigns and — if the socket is connected — subscribes to
      every widget topic the banners need.

      Pass the banners you intend to render so per-banner selection topics
      get subscribed to and per-banner impressions get incremented. Safe to
      call with `banners = []`.
      """
      def mount_widgets(socket, banners) when is_list(banners) do
        widget_banners = Enum.filter(banners, fn b -> b.widget_type end)

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, @widget_fs_feed_topic)
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, @widget_rt_bots_topic)

          for banner <- widget_banners do
            Phoenix.PubSub.subscribe(
              BlocksterV2.PubSub,
              @widget_selection_topic_prefix <> Integer.to_string(banner.id)
            )

            Ads.increment_impressions(banner.id)
          end

          # Subscribe to chart topics for any RogueTrader selection we
          # already know about at mount time so updates flow immediately.
          for {_banner_id, {bot_id, tf}} <- __initial_selections__(widget_banners),
              is_binary(bot_id) and is_binary(tf) do
            Phoenix.PubSub.subscribe(
              BlocksterV2.PubSub,
              @widget_rt_chart_topic_prefix <> "#{bot_id}_#{tf}"
            )
          end
        end

        socket
        |> Phoenix.Component.assign(:fs_trades, FateSwapFeedTracker.get_trades())
        |> Phoenix.Component.assign(:rt_bots, RogueTraderBotsTracker.get_bots())
        |> Phoenix.Component.assign(:widget_selections, __initial_selections__(widget_banners))
        |> Phoenix.Component.assign(:widget_chart_data, __initial_chart_data__(widget_banners))
        |> Phoenix.Component.assign(:widget_tracker_errors, TrackerStatus.errors())
      end

      # ── handle_info ────────────────────────────────────────────────────

      def handle_info({:fs_trades, trades}, socket) do
        {:noreply,
         socket
         |> Phoenix.Component.assign(:fs_trades, trades)
         |> Phoenix.Component.assign(:widget_tracker_errors, TrackerStatus.errors())
         |> Phoenix.LiveView.push_event("widget:fs_feed:update", %{trades: trades})}
      end

      def handle_info({:rt_bots, bots}, socket) do
        {:noreply,
         socket
         |> Phoenix.Component.assign(:rt_bots, bots)
         |> Phoenix.Component.assign(:widget_tracker_errors, TrackerStatus.errors())
         |> Phoenix.LiveView.push_event("widget:rt_bots:update", %{bots: bots})}
      end

      def handle_info({:rt_chart, bot_id, tf, points}, socket) do
        chart_data =
          Map.get(socket.assigns, :widget_chart_data, %{})

        updated = Map.put(chart_data, {bot_id, tf}, points)

        {:noreply,
         socket
         |> Phoenix.Component.assign(:widget_chart_data, updated)
         |> Phoenix.LiveView.push_event("widget:rt_chart:update", %{
           bot_id: bot_id,
           tf: tf,
           points: points
         })}
      end

      def handle_info({:selection_changed, banner_id, subject}, socket) do
        selections =
          socket.assigns
          |> Map.get(:widget_selections, %{})
          |> Map.put(banner_id, subject)

        socket = Phoenix.Component.assign(socket, :widget_selections, selections)

        case subject do
          {bot_id, tf} when is_binary(bot_id) and is_binary(tf) ->
            Phoenix.PubSub.subscribe(
              BlocksterV2.PubSub,
              @widget_rt_chart_topic_prefix <> "#{bot_id}_#{tf}"
            )

            points = RogueTraderChartTracker.get_series(bot_id, tf)

            chart_data =
              socket.assigns
              |> Map.get(:widget_chart_data, %{})
              |> Map.put({bot_id, tf}, points)

            {:noreply,
             socket
             |> Phoenix.Component.assign(:widget_chart_data, chart_data)
             |> Phoenix.LiveView.push_event("widget:#{banner_id}:select", %{
               bot_id: bot_id,
               tf: tf,
               points: points
             })}

          order_id when is_binary(order_id) ->
            order = FateSwapFeedTracker.get_order(order_id)

            {:noreply,
             Phoenix.LiveView.push_event(socket, "widget:#{banner_id}:select", %{
               order_id: order_id,
               order: order
             })}

          nil ->
            {:noreply, socket}
        end
      end

      # ── handle_event ───────────────────────────────────────────────────

      def handle_event("widget_click", %{"banner_id" => banner_id} = params, socket) do
        subject = __normalize_subject__(Map.get(params, "subject"))

        case __parse_banner_id__(banner_id) do
          {:ok, id} ->
            Ads.increment_clicks(id)
            {:noreply, Phoenix.LiveView.redirect(socket, external: ClickRouter.url_for(id, subject))}

          :error ->
            {:noreply, socket}
        end
      end

      # ── Internal helpers (prefixed so host LiveViews don't clash) ──────

      @doc false
      def __initial_selections__(widget_banners) do
        Enum.reduce(widget_banners, %{}, fn banner, acc ->
          case :mnesia.dirty_read(:widget_selections, banner.id) do
            [{:widget_selections, _, _, subject, _}] -> Map.put(acc, banner.id, subject)
            _ -> acc
          end
        end)
      end

      @doc false
      def __initial_chart_data__(widget_banners) do
        for banner <- widget_banners,
            {:widget_selections, _, _, {bot_id, tf}, _} <-
              :mnesia.dirty_read(:widget_selections, banner.id),
            is_binary(bot_id),
            is_binary(tf),
            into: %{} do
          {{bot_id, tf}, RogueTraderChartTracker.get_series(bot_id, tf)}
        end
      end

      @doc false
      def __normalize_subject__(%{"bot_id" => bot_id, "tf" => tf})
          when is_binary(bot_id) and is_binary(tf),
          do: {bot_id, tf}

      def __normalize_subject__(subject) when is_binary(subject), do: subject
      def __normalize_subject__(_), do: nil

      @doc false
      def __parse_banner_id__(id) when is_integer(id), do: {:ok, id}

      def __parse_banner_id__(id) when is_binary(id) do
        case Integer.parse(id) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
      end

      def __parse_banner_id__(_), do: :error
    end
  end
end
