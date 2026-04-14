defmodule BlocksterV2.Widgets.RogueTraderBotsTrackerTest do
  use BlocksterV2.DataCase, async: false

  import BlocksterV2.Widgets.MnesiaCase, only: [setup_widget_mnesia: 1]

  alias BlocksterV2.Ads
  alias BlocksterV2.Widgets.RogueTraderBotsTracker

  setup :setup_widget_mnesia

  setup do
    stub = :"RTBotsTrackerStub_#{:erlang.unique_integer([:positive, :monotonic])}"
    Req.Test.stub(stub, fn conn -> Plug.Conn.send_resp(conn, 503, "not set") end)

    opts = [
      name: :"rt_bots_tracker_#{:erlang.unique_integer([:positive, :monotonic])}",
      base_url: "http://stub.test",
      path: "/api/bots",
      req_options: [plug: {Req.Test, stub}],
      auto_start: false,
      skip_global: true,
      interval: 60_000
    ]

    {:ok, pid} = GenServer.start_link(RogueTraderBotsTracker, opts)
    Req.Test.allow(stub, self(), pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    %{pid: pid, stub: stub}
  end

  defp bot(id, overrides \\ %{}) do
    base = %{
      "bot_id" => id,
      "slug" => id,
      "name" => String.upcase(id),
      "lp_price" => 1.0,
      "lp_price_change_1h_pct" => 0.5,
      "lp_price_change_6h_pct" => 0.5,
      "lp_price_change_24h_pct" => 0.5,
      "lp_price_change_48h_pct" => 0.5,
      "lp_price_change_7d_pct" => 0.5,
      "sol_balance" => 1.0,
      "rank" => 1
    }

    Map.merge(base, overrides)
  end

  defp stub_bots(stub, bots) do
    Req.Test.stub(stub, fn conn ->
      assert conn.request_path == "/api/bots"
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, Jason.encode!(bots))
    end)
  end

  test "happy path caches bots + broadcasts", %{pid: pid, stub: stub} do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader:bots")
    stub_bots(stub, [bot("a"), bot("b")])

    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert_receive {:rt_bots, bots}, 1_000
    assert length(bots) == 2
    assert length(RogueTraderBotsTracker.get_bots()) == 2
  end

  test "accepts {bots: [...]} wrapped payload", %{pid: pid, stub: stub} do
    Req.Test.stub(stub, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, Jason.encode!(%{"bots" => [bot("a")]}))
    end)

    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert [%{"slug" => "a"}] = RogueTraderBotsTracker.get_bots()
  end

  test "upstream 500 preserves cache", %{pid: pid, stub: stub} do
    stub_bots(stub, [bot("a")])
    :ok = RogueTraderBotsTracker.poll_now(pid)

    Req.Test.stub(stub, fn conn -> Plug.Conn.send_resp(conn, 500, "{}") end)
    :ok = RogueTraderBotsTracker.poll_now(pid)

    assert [%{"slug" => "a"}] = RogueTraderBotsTracker.get_bots()
  end

  test "transport error preserves cache", %{pid: pid, stub: stub} do
    stub_bots(stub, [bot("a")])
    :ok = RogueTraderBotsTracker.poll_now(pid)

    Req.Test.stub(stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert [%{"slug" => "a"}] = RogueTraderBotsTracker.get_bots()
  end

  test "non-list payload is ignored", %{pid: pid, stub: stub} do
    Req.Test.stub(stub, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, Jason.encode!(%{"wrong" => "shape"}))
    end)

    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert RogueTraderBotsTracker.get_bots() == []
  end

  test "change detection: no broadcast on identical snapshot", %{pid: pid, stub: stub} do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader:bots")
    stub_bots(stub, [bot("a")])

    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert_receive {:rt_bots, _}, 1_000

    :ok = RogueTraderBotsTracker.poll_now(pid)
    refute_receive {:rt_bots, _}, 200

    # Price change triggers broadcast
    stub_bots(stub, [bot("a", %{"lp_price" => 1.5})])
    :ok = RogueTraderBotsTracker.poll_now(pid)
    assert_receive {:rt_bots, _}, 1_000
  end

  test "selector refresh per banner", %{pid: pid, stub: stub} do
    {:ok, banner} =
      Ads.create_banner(%{
        name: "rt-chart",
        placement: "sidebar_right",
        widget_type: "rt_chart_landscape",
        widget_config: %{"selection" => "biggest_gainer"}
      })

    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:selection:#{banner.id}")

    bots = [
      bot("low", %{"lp_price_change_7d_pct" => 0.2}),
      bot("high", %{"lp_price_change_7d_pct" => 12.0})
    ]

    stub_bots(stub, bots)
    :ok = RogueTraderBotsTracker.poll_now(pid)

    assert_receive {:selection_changed, banner_id, {"high", "7d"}}, 1_000
    assert banner_id == banner.id

    # Same pick → no broadcast
    :ok = RogueTraderBotsTracker.poll_now(pid)
    refute_receive {:selection_changed, _, _}, 200
  end
end
