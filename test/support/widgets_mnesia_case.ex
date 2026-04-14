defmodule BlocksterV2.Widgets.MnesiaCase do
  @moduledoc """
  Test helper that ensures the 4 widget Mnesia tables exist (ram-only)
  and clears them between tests.

  Follows the existing convention in the codebase (see e.g.
  `test/blockster_v2_web/live/airdrop_live_test.exs`) of bringing up
  Mnesia inside the test suite because `start_genservers` is false in
  the test env, so `MnesiaInitializer` is not started.

  Usage:

      setup :setup_widget_mnesia
  """

  @tables [
    {:widget_fs_feed_cache, [:id, :trades, :fetched_at]},
    {:widget_rt_bots_cache, [:id, :bots, :fetched_at]},
    {:widget_rt_chart_cache,
     [:key, :bot_id, :timeframe, :points, :high, :low, :change_pct, :fetched_at]},
    {:widget_selections, [:banner_id, :widget_type, :subject, :picked_at]}
  ]

  def setup_widget_mnesia(_context) do
    :mnesia.start()
    ensure_tables()
    clear_tables()
    :ok
  end

  def ensure_tables do
    for {table, attrs} <- @tables do
      case :mnesia.create_table(table, attributes: attrs, type: :set, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        {:aborted, other} -> raise "Mnesia table creation failed for #{table}: #{inspect(other)}"
      end
    end

    :ok
  end

  def clear_tables do
    for {table, _} <- @tables do
      :mnesia.clear_table(table)
    end

    :ok
  end

  def tables, do: Enum.map(@tables, fn {t, _} -> t end)
end
