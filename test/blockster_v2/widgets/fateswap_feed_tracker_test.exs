defmodule BlocksterV2.Widgets.FateSwapFeedTrackerTest do
  use BlocksterV2.DataCase, async: false

  import BlocksterV2.Widgets.MnesiaCase, only: [setup_widget_mnesia: 1]

  alias BlocksterV2.Ads
  alias BlocksterV2.Widgets.FateSwapFeedTracker

  setup :setup_widget_mnesia

  setup ctx do
    stub = :"FateSwapFeedTrackerStub_#{:erlang.unique_integer([:positive, :monotonic])}"

    opts =
      [
        name: :"fs_feed_tracker_#{:erlang.unique_integer([:positive, :monotonic])}",
        base_url: "http://stub.test",
        path: "/api/feed/recent?limit=20",
        req_options: [plug: {Req.Test, stub}],
        auto_start: false,
        skip_global: true,
        interval: 60_000
      ]
      |> Keyword.merge(Map.get(ctx, :extra_opts, []))

    # Initial stub so Req.Test.allow has something to link; tests override.
    Req.Test.stub(stub, fn conn -> Plug.Conn.send_resp(conn, 503, "not set") end)

    {:ok, pid} = GenServer.start_link(FateSwapFeedTracker, opts)
    Req.Test.allow(stub, self(), pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    %{pid: pid, stub: stub}
  end

  defp trade(id, overrides \\ %{}) do
    base = %{
      "id" => id,
      "side" => "buy",
      "status_text" => "DISCOUNT FILLED",
      "filled" => true,
      "profit_lamports" => 1_000,
      "discount_pct" => 5.0,
      "settled_at" => 1_700_000_000
    }

    Map.merge(base, overrides)
  end

  defp stub_respond(stub, {status, body}) do
    Req.Test.stub(stub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/feed/recent"
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end

  describe "happy path poll" do
    test "caches trades in Mnesia and broadcasts {:fs_trades, trades}", %{pid: pid, stub: stub} do
      trades = [trade("a"), trade("b")]
      stub_respond(stub, {200, trades})

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:fateswap:feed")
      :ok = FateSwapFeedTracker.poll_now(pid)

      assert_receive {:fs_trades, received}, 1_000
      assert length(received) == 2

      cached = FateSwapFeedTracker.get_trades()
      assert length(cached) == 2
      assert FateSwapFeedTracker.last_fetched_at() > 0
    end

    test "accepts {trades: [...]} wrapped payload", %{pid: pid, stub: stub} do
      stub_respond(stub, {200, %{"trades" => [trade("a")]}})

      :ok = FateSwapFeedTracker.poll_now(pid)
      assert [%{"id" => "a"}] = FateSwapFeedTracker.get_trades()
    end
  end

  describe "failure modes" do
    test "upstream 500 keeps last good cache", %{pid: pid, stub: stub} do
      stub_respond(stub, {200, [trade("a")]})
      :ok = FateSwapFeedTracker.poll_now(pid)
      assert [%{"id" => "a"}] = FateSwapFeedTracker.get_trades()

      stub_respond(stub, {500, %{"error" => "boom"}})
      :ok = FateSwapFeedTracker.poll_now(pid)

      # cache is preserved
      assert [%{"id" => "a"}] = FateSwapFeedTracker.get_trades()
    end

    test "transport failure keeps last good cache", %{pid: pid, stub: stub} do
      stub_respond(stub, {200, [trade("a")]})
      :ok = FateSwapFeedTracker.poll_now(pid)

      Req.Test.stub(stub, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      :ok = FateSwapFeedTracker.poll_now(pid)
      assert [%{"id" => "a"}] = FateSwapFeedTracker.get_trades()
    end

    test "empty payload stores []", %{pid: pid, stub: stub} do
      stub_respond(stub, {200, []})
      :ok = FateSwapFeedTracker.poll_now(pid)
      assert FateSwapFeedTracker.get_trades() == []
    end

    test "non-list payload is ignored", %{pid: pid, stub: stub} do
      stub_respond(stub, {200, %{"unexpected" => "shape"}})
      :ok = FateSwapFeedTracker.poll_now(pid)
      # nothing written
      assert FateSwapFeedTracker.get_trades() == []
    end
  end

  describe "change detection" do
    test "broadcasts only when trade ids list changes", %{pid: pid, stub: stub} do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:fateswap:feed")

      stub_respond(stub, {200, [trade("a"), trade("b")]})
      :ok = FateSwapFeedTracker.poll_now(pid)
      assert_receive {:fs_trades, _}, 1_000

      # Same ids again — no broadcast
      :ok = FateSwapFeedTracker.poll_now(pid)
      refute_receive {:fs_trades, _}, 200

      # Different ids — broadcast
      stub_respond(stub, {200, [trade("a"), trade("c")]})
      :ok = FateSwapFeedTracker.poll_now(pid)
      assert_receive {:fs_trades, _}, 1_000
    end
  end

  describe "selector refresh" do
    test "writes widget_selections row and broadcasts per banner", %{pid: pid, stub: stub} do
      {:ok, banner} =
        Ads.create_banner(%{
          name: "fs-hero",
          placement: "sidebar_right",
          widget_type: "fs_hero_portrait",
          widget_config: %{"selection" => "biggest_profit"}
        })

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:selection:#{banner.id}")

      trades = [trade("small", %{"profit_lamports" => 10}), trade("big", %{"profit_lamports" => 9_999})]
      stub_respond(stub, {200, trades})

      :ok = FateSwapFeedTracker.poll_now(pid)

      assert_receive {:selection_changed, banner_id, subject}, 1_000
      assert banner_id == banner.id
      assert subject == "big"

      # Polling again with the same top order = no new broadcast
      :ok = FateSwapFeedTracker.poll_now(pid)
      refute_receive {:selection_changed, _, _}, 200
    end
  end
end
