# Export Mnesia data to ETF files for production seeding
#
# Usage: elixir --sname exporter$RANDOM scripts/export_to_json.exs
#
# This connects to the running hr1 node and exports all Mnesia tables to priv/mnesia_seed/

target_node = :"hr1@Adams-iMac-Pro"
output_dir = Path.join([__DIR__, "..", "priv", "mnesia_seed"]) |> Path.expand()

IO.puts("Connecting to #{target_node}...")

case Node.connect(target_node) do
  true ->
    IO.puts("Connected!")
  false ->
    IO.puts("ERROR: Could not connect to #{target_node}")
    IO.puts("Make sure hr1 is running: elixir --sname hr1 -S mix phx.server")
    System.halt(1)
end

# Wait for connection to stabilize
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

IO.puts("\nExporting to #{output_dir}")
File.mkdir_p!(output_dir)

total_records = 0

# Export each table
Enum.reduce(tables, 0, fn table, total ->
  IO.write("  #{table}... ")

  match_spec = [{:"$1", [], [:"$1"]}]
  records = :rpc.call(target_node, :mnesia, :dirty_select, [table, match_spec])

  case records do
    list when is_list(list) ->
      # Write as Erlang Term Format (binary, compressed)
      binary = :erlang.term_to_binary(list, [:compressed])
      file_path = Path.join(output_dir, "#{table}.etf")
      File.write!(file_path, binary)

      size = byte_size(binary)
      size_str = if size > 1024, do: "#{Float.round(size / 1024, 1)} KB", else: "#{size} B"
      IO.puts("#{length(list)} records (#{size_str})")
      total + length(list)

    {:badrpc, reason} ->
      IO.puts("ERROR: #{inspect(reason)}")
      total
  end
end)
|> then(fn total ->
  IO.puts("\nTotal: #{total} records exported")
  IO.puts("Files written to priv/mnesia_seed/")
  IO.puts("\nThese files will be bundled with the release and used to seed production Mnesia on first startup.")
end)
