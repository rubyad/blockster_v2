# Production Migration Script: Reset all BUX pool values to 0
#
# This script sets bux_balance, bux_deposited, and total_distributed to 0 for
# all records in the post_bux_points Mnesia table.
#
# Usage:
#   # Connect to production via SSH
#   flyctl ssh console -a blockster-v2
#
#   # Run the script
#   /app/bin/blockster_v2 eval "Code.require_file(\"/app/priv/scripts/reset_post_bux_pools.exs\")"
#
#   # Or run via RPC from a local node connected to the cluster
#   elixir --sname admin -S mix run priv/scripts/reset_post_bux_pools.exs
#

defmodule ResetPostBuxPools do
  require Logger

  def run do
    IO.puts("\n=== Reset Post BUX Pools ===\n")

    # Check if Mnesia is running
    case :mnesia.system_info(:is_running) do
      :yes ->
        IO.puts("✓ Mnesia is running")
        reset_pools()

      status ->
        IO.puts("✗ Mnesia is not running: #{inspect(status)}")
        {:error, :mnesia_not_running}
    end
  end

  defp reset_pools do
    # Get all records from post_bux_points table
    records = :mnesia.dirty_match_object({:post_bux_points, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})

    IO.puts("Found #{length(records)} post_bux_points records\n")

    if length(records) == 0 do
      IO.puts("No records to reset. Done.")
      {:ok, 0}
    else
      # Show preview of what will be reset
      IO.puts("Preview of records to reset:")
      IO.puts("-----------------------------")

      Enum.each(records, fn record ->
        post_id = elem(record, 1)
        balance = elem(record, 4) || 0
        deposited = elem(record, 5) || 0
        distributed = elem(record, 6) || 0

        if balance > 0 or deposited > 0 or distributed > 0 do
          IO.puts("Post #{post_id}: balance=#{balance}, deposited=#{deposited}, distributed=#{distributed}")
        end
      end)

      IO.puts("\n")

      # Ask for confirmation
      IO.puts("This will set bux_balance, bux_deposited, and total_distributed to 0 for ALL #{length(records)} records.")
      response = IO.gets("Are you sure you want to proceed? (yes/no): ") |> String.trim()

      if response == "yes" do
        do_reset(records)
      else
        IO.puts("Aborted.")
        {:ok, :aborted}
      end
    end
  end

  defp do_reset(records) do
    now = System.system_time(:second)
    reset_count = 0

    results = Enum.map(records, fn record ->
      post_id = elem(record, 1)

      # Set bux_balance (4), bux_deposited (5), total_distributed (6) to 0
      # Update updated_at (11) to now
      updated = record
        |> put_elem(4, 0)       # bux_balance
        |> put_elem(5, 0)       # bux_deposited
        |> put_elem(6, 0)       # total_distributed
        |> put_elem(11, now)    # updated_at

      :mnesia.dirty_write(updated)
      IO.puts("✓ Reset post #{post_id}")
      :ok
    end)

    success_count = Enum.count(results, &(&1 == :ok))

    IO.puts("\n=== Complete ===")
    IO.puts("Reset #{success_count} of #{length(records)} records to 0")

    {:ok, success_count}
  end
end

# Run the migration
ResetPostBuxPools.run()
