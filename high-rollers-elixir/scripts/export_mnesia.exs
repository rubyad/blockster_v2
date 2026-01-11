#!/usr/bin/env elixir
# Export Mnesia data from running hr1 node
#
# Usage:
#   elixir --sname export -S mix run --no-start scripts/export_mnesia.exs
#

target_node = :"hr1@Adams-iMac-Pro"
output_file = "/tmp/hr_mnesia_export.etf"

IO.puts("\n=== Mnesia Export Script ===")
IO.puts("Target node: #{target_node}")
IO.puts("Output file: #{output_file}")

# Connect to running node
IO.puts("\nConnecting to #{target_node}...")
case Node.connect(target_node) do
  true ->
    IO.puts("✅ Connected!")

  false ->
    IO.puts("❌ Failed to connect to #{target_node}")
    IO.puts("Make sure hr1 is running: elixir --sname hr1 -S mix phx.server")
    System.halt(1)
end

:timer.sleep(1000)

# Tables to export
tables = [
  :hr_nfts,
  :hr_reward_events,
  :hr_reward_withdrawals,
  :hr_users,
  :hr_affiliate_earnings,
  :hr_stats,
  :hr_poller_state,
  :hr_prices
]

IO.puts("\nExporting tables: #{inspect(tables)}")

# Export each table via RPC using dirty_select (works across nodes)
data = Enum.reduce(tables, %{}, fn table, acc ->
  # Use dirty_select with a match spec that returns all records
  # Match spec: [{pattern, guards, result}] where pattern matches all, result returns whole object
  match_spec = [{:"$1", [], [:"$1"]}]
  records = :rpc.call(target_node, :mnesia, :dirty_select, [table, match_spec])

  count = case records do
    list when is_list(list) -> length(list)
    {:badrpc, reason} ->
      IO.puts("  ⚠️  #{table}: RPC error: #{inspect(reason)}")
      0
    _ -> 0
  end

  IO.puts("  #{table}: #{count} records")
  Map.put(acc, table, records)
end)

# Build export data
export_data = %{
  version: 1,
  exported_at: System.system_time(:second),
  exported_from: target_node,
  tables: data,
  record_counts: Enum.map(data, fn {table, records} ->
    {table, if(is_list(records), do: length(records), else: 0)}
  end) |> Map.new()
}

# Write to file
binary = :erlang.term_to_binary(export_data, [:compressed])
File.write!(output_file, binary)

total = Enum.sum(Map.values(export_data.record_counts))
file_size = File.stat!(output_file).size
size_str = cond do
  file_size < 1024 -> "#{file_size} B"
  file_size < 1024 * 1024 -> "#{Float.round(file_size / 1024, 1)} KB"
  true -> "#{Float.round(file_size / 1024 / 1024, 1)} MB"
end

IO.puts("\n✅ Export complete!")
IO.puts("   Total records: #{total}")
IO.puts("   File size: #{size_str}")
IO.puts("   File: #{output_file}")

IO.puts("\n=== Next Steps ===")
IO.puts("1. Copy to production:")
IO.puts("   flyctl ssh sftp shell -a high-rollers-elixir")
IO.puts("   put #{output_file} /tmp/hr_mnesia_export.etf")
IO.puts("")
IO.puts("2. Import in production:")
IO.puts("   flyctl ssh console -a high-rollers-elixir -C '/app/bin/high_rollers remote'")
IO.puts("   HighRollers.MnesiaSync.import_all(\"/tmp/hr_mnesia_export.etf\")")
IO.puts("")
