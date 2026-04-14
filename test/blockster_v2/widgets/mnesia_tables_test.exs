defmodule BlocksterV2.Widgets.MnesiaTablesTest do
  use ExUnit.Case, async: false

  import BlocksterV2.Widgets.MnesiaCase, only: [setup_widget_mnesia: 1, ensure_tables: 0]

  setup :setup_widget_mnesia

  test "all 4 widget tables exist after init" do
    for table <- BlocksterV2.Widgets.MnesiaCase.tables() do
      assert :mnesia.table_info(table, :type) in [:set, :ordered_set]
    end
  end

  test "dirty_write + dirty_read round-trips for fs feed cache" do
    trades = [%{"id" => "a"}]
    :mnesia.dirty_write({:widget_fs_feed_cache, :singleton, trades, 123})

    assert [{:widget_fs_feed_cache, :singleton, ^trades, 123}] =
             :mnesia.dirty_read(:widget_fs_feed_cache, :singleton)
  end

  test "dirty_write + dirty_read round-trips for rt bots cache" do
    bots = [%{"slug" => "kronos"}]
    :mnesia.dirty_write({:widget_rt_bots_cache, :singleton, bots, 123})

    assert [{:widget_rt_bots_cache, :singleton, ^bots, 123}] =
             :mnesia.dirty_read(:widget_rt_bots_cache, :singleton)
  end

  test "chart cache uses composite {bot_id, tf} key" do
    :mnesia.dirty_write({:widget_rt_chart_cache, {"kronos", "1h"}, "kronos", "1h",
      [%{"time" => 1}], 1.2, 1.0, 20.0, 123})

    assert [{:widget_rt_chart_cache, {"kronos", "1h"}, "kronos", "1h", _, _, _, _, _}] =
             :mnesia.dirty_read(:widget_rt_chart_cache, {"kronos", "1h"})

    assert :mnesia.dirty_read(:widget_rt_chart_cache, {"apollo", "1h"}) == []
  end

  test "widget_selections keyed by banner_id" do
    :mnesia.dirty_write({:widget_selections, 42, "rt_skyscraper", {"kronos", "7d"}, 123})

    assert [{:widget_selections, 42, "rt_skyscraper", {"kronos", "7d"}, 123}] =
             :mnesia.dirty_read(:widget_selections, 42)
  end

  test "re-init is idempotent" do
    assert :ok = ensure_tables()
    assert :ok = ensure_tables()
  end
end
