defmodule BlocksterV2.Widgets.RogueTraderChartTrackerTest do
  use ExUnit.Case, async: false

  import BlocksterV2.Widgets.MnesiaCase, only: [setup_widget_mnesia: 1]

  alias BlocksterV2.Widgets.RogueTraderChartTracker

  setup :setup_widget_mnesia

  setup do
    stub = :"RTChartTrackerStub_#{:erlang.unique_integer([:positive, :monotonic])}"
    Req.Test.stub(stub, fn conn -> Plug.Conn.send_resp(conn, 503, "not set") end)

    opts = [
      name: :"rt_chart_tracker_#{:erlang.unique_integer([:positive, :monotonic])}",
      base_url: "http://stub.test",
      req_options: [plug: {Req.Test, stub}],
      auto_start: false,
      skip_global: true,
      interval: 60_000,
      bot_ids: ["kronos", "apollo"]
    ]

    {:ok, pid} = GenServer.start_link(RogueTraderChartTracker, opts)
    Req.Test.allow(stub, self(), pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    %{pid: pid, stub: stub}
  end

  defp stub_series(stub, body_fun) do
    Req.Test.stub(stub, fn conn ->
      assert String.starts_with?(conn.request_path, "/api/bots/")
      assert String.ends_with?(conn.request_path, "/chart")

      payload = body_fun.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(payload))
    end)
  end

  test "caches points/high/low/change_pct and broadcasts per series", %{pid: pid, stub: stub} do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader:chart:kronos_1h")

    stub_series(stub, fn _conn ->
      %{
        "bot_id" => "kronos",
        "timeframe" => "1h",
        "points" => [%{"time" => 1, "value" => 1.0}, %{"time" => 2, "value" => 1.2}],
        "high" => 1.2,
        "low" => 1.0,
        "change_pct" => 20.0
      }
    end)

    :ok = RogueTraderChartTracker.poll_now(pid, "kronos", "1h")

    assert_receive {:rt_chart, "kronos", "1h", points}, 1_000
    assert length(points) == 2

    assert RogueTraderChartTracker.get_series("kronos", "1h") == [
             %{"time" => 1, "value" => 1.0},
             %{"time" => 2, "value" => 1.2}
           ]

    assert RogueTraderChartTracker.get_change_pct("kronos", "1h") == 20.0
    assert RogueTraderChartTracker.get_high_low("kronos", "1h") == %{high: 1.2, low: 1.0}
  end

  test "upstream 500 leaves cache untouched", %{pid: pid, stub: stub} do
    # seed a cached series first
    stub_series(stub, fn _ ->
      %{"bot_id" => "apollo", "timeframe" => "24h", "points" => [%{"time" => 1, "value" => 9.0}], "high" => 9, "low" => 9, "change_pct" => 0}
    end)

    :ok = RogueTraderChartTracker.poll_now(pid, "apollo", "24h")
    assert [%{"value" => 9.0}] = RogueTraderChartTracker.get_series("apollo", "24h")

    Req.Test.stub(stub, fn conn -> Plug.Conn.send_resp(conn, 500, "{}") end)
    :ok = RogueTraderChartTracker.poll_now(pid, "apollo", "24h")
    assert [%{"value" => 9.0}] = RogueTraderChartTracker.get_series("apollo", "24h")
  end

  test "unknown bot/tf returns [] / nil", %{pid: _pid} do
    assert RogueTraderChartTracker.get_series("never", "7d") == []
    assert RogueTraderChartTracker.get_change_pct("never", "7d") == nil
    assert RogueTraderChartTracker.get_high_low("never", "7d") == nil
  end

  test "timeframes/0 returns the 5 supported tfs" do
    assert RogueTraderChartTracker.timeframes() == ~w(1h 6h 24h 48h 7d)
  end

  test "non-map response is ignored", %{pid: pid, stub: stub} do
    Req.Test.stub(stub, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, Jason.encode!([1, 2, 3]))
    end)

    :ok = RogueTraderChartTracker.poll_now(pid, "kronos", "6h")
    assert RogueTraderChartTracker.get_series("kronos", "6h") == []
  end
end
