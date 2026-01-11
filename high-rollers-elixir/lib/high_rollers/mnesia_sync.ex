defmodule HighRollers.MnesiaSync do
  @moduledoc """
  Export and import Mnesia data for syncing between local development and production.

  ## Usage

  ### Export from local (connect to running hr1 node):
      # In a new terminal:
      elixir --sname sync -S mix run -e '
        Node.connect(:"hr1@Adams-iMac-Pro")
        :timer.sleep(2000)
        HighRollers.MnesiaSync.export_from_node(:"hr1@Adams-iMac-Pro", "/tmp/hr_mnesia_export.etf")
      '

  ### Or from IEx connected to hr1:
      HighRollers.MnesiaSync.export_all("/tmp/hr_mnesia_export.etf")

  ### Copy to production:
      flyctl ssh sftp shell -a high-rollers-elixir
      put /tmp/hr_mnesia_export.etf /tmp/hr_mnesia_export.etf

  ### Import in production (run via remote console):
      flyctl ssh console -a high-rollers-elixir -C '/app/bin/high_rollers remote'
      HighRollers.MnesiaSync.import_all("/tmp/hr_mnesia_export.etf")

  ## Tables Exported:
  - hr_nfts - All NFT data with earnings and time rewards
  - hr_reward_events - Historical reward events
  - hr_reward_withdrawals - User withdrawal history
  - hr_users - User-affiliate mappings
  - hr_affiliate_earnings - Affiliate commission records
  - hr_stats - Global and per-hostess statistics
  - hr_poller_state - Block number tracking (optional)
  - hr_prices - Price cache (optional, will refresh)

  ## Format:
  Uses Erlang Term Format (.etf) for efficient binary serialization.
  """

  require Logger

  @tables_to_sync [
    :hr_nfts,
    :hr_reward_events,
    :hr_reward_withdrawals,
    :hr_users,
    :hr_affiliate_earnings,
    :hr_stats,
    :hr_poller_state,
    :hr_prices
  ]

  # Tables that should be cleared before import (vs merged)
  @replace_tables [
    :hr_nfts,
    :hr_users,
    :hr_stats,
    :hr_poller_state,
    :hr_prices
  ]

  @doc """
  Export Mnesia data from a remote node via RPC.
  Use this when running from a separate process that connects to the running node.

  ## Example
      Node.connect(:"hr1@Adams-iMac-Pro")
      HighRollers.MnesiaSync.export_from_node(:"hr1@Adams-iMac-Pro", "/tmp/hr_mnesia_export.etf")
  """
  def export_from_node(node, file_path, opts \\ []) do
    tables = Keyword.get(opts, :tables, @tables_to_sync)

    IO.puts("[MnesiaSync] Exporting from node #{node} to #{file_path}")
    IO.puts("[MnesiaSync] Tables: #{inspect(tables)}")

    data = Enum.reduce(tables, %{}, fn table, acc ->
      records = :rpc.call(node, __MODULE__, :get_table_records, [table])
      count = if is_list(records), do: length(records), else: 0
      IO.puts("[MnesiaSync] Exported #{count} records from #{table}")
      Map.put(acc, table, records)
    end)

    # Add metadata
    export_data = %{
      version: 1,
      exported_at: System.system_time(:second),
      exported_from: node,
      tables: data,
      record_counts: Enum.map(data, fn {table, records} ->
        {table, if(is_list(records), do: length(records), else: 0)}
      end) |> Map.new()
    }

    # Write to file using Erlang Term Format
    binary = :erlang.term_to_binary(export_data, [:compressed])
    File.write!(file_path, binary)

    total = Enum.sum(Map.values(export_data.record_counts))
    file_size = File.stat!(file_path).size
    IO.puts("[MnesiaSync] Export complete: #{total} records, #{format_bytes(file_size)}")

    {:ok, %{
      file: file_path,
      records: total,
      size: file_size,
      tables: export_data.record_counts
    }}
  end

  @doc """
  Get all records from a table. Called via RPC from export_from_node.
  """
  def get_table_records(table) do
    :mnesia.activity(:async_dirty, fn ->
      :mnesia.foldl(fn record, acc -> [record | acc] end, [], table)
    end)
  rescue
    e -> {:error, inspect(e)}
  end

  @doc """
  Export all Mnesia tables to a file.
  Run this directly on the node with Mnesia tables (e.g., in IEx).

  ## Options
  - :tables - List of specific tables to export (default: all)
  - :include_stats - Include stats table (default: true)

  ## Example
      HighRollers.MnesiaSync.export_all("/tmp/mnesia_export.etf")
  """
  def export_all(file_path, opts \\ []) do
    tables = Keyword.get(opts, :tables, @tables_to_sync)

    Logger.info("[MnesiaSync] Starting export to #{file_path}")
    Logger.info("[MnesiaSync] Tables: #{inspect(tables)}")

    data = Enum.reduce(tables, %{}, fn table, acc ->
      records = get_table_records(table)
      count = if is_list(records), do: length(records), else: 0
      Logger.info("[MnesiaSync] Exported #{count} records from #{table}")
      Map.put(acc, table, records)
    end)

    # Add metadata
    export_data = %{
      version: 1,
      exported_at: System.system_time(:second),
      exported_from: node(),
      tables: data,
      record_counts: Enum.map(data, fn {table, records} -> {table, length(records)} end) |> Map.new()
    }

    # Write to file using Erlang Term Format
    binary = :erlang.term_to_binary(export_data, [:compressed])
    File.write!(file_path, binary)

    total = Enum.sum(Map.values(export_data.record_counts))
    file_size = File.stat!(file_path).size
    Logger.info("[MnesiaSync] Export complete: #{total} records, #{format_bytes(file_size)}")

    {:ok, %{
      file: file_path,
      records: total,
      size: file_size,
      tables: export_data.record_counts
    }}
  end

  @doc """
  Import Mnesia data from a file.

  ## Options
  - :tables - List of specific tables to import (default: all in file)
  - :mode - :replace (clear table first) or :merge (keep existing) - default varies by table
  - :dry_run - If true, just show what would be imported (default: false)

  ## Example
      HighRollers.MnesiaSync.import_all("/tmp/mnesia_export.etf")
      HighRollers.MnesiaSync.import_all("/tmp/mnesia_export.etf", dry_run: true)
  """
  def import_all(file_path, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    Logger.info("[MnesiaSync] Starting import from #{file_path}#{if dry_run, do: " (DRY RUN)"}")

    # Read and decode file
    binary = File.read!(file_path)
    export_data = :erlang.binary_to_term(binary)

    Logger.info("[MnesiaSync] Export version: #{export_data.version}")
    Logger.info("[MnesiaSync] Exported at: #{format_timestamp(export_data.exported_at)}")
    Logger.info("[MnesiaSync] Exported from: #{export_data.exported_from}")
    Logger.info("[MnesiaSync] Record counts: #{inspect(export_data.record_counts)}")

    tables_to_import = Keyword.get(opts, :tables, Map.keys(export_data.tables))

    if dry_run do
      Logger.info("[MnesiaSync] DRY RUN - no changes made")
      {:ok, %{dry_run: true, tables: export_data.record_counts}}
    else
      results = Enum.map(tables_to_import, fn table ->
        records = Map.get(export_data.tables, table, [])
        result = import_table(table, records, opts)
        {table, result}
      end)

      total_imported = Enum.sum(Enum.map(results, fn {_, {:ok, count}} -> count end))
      Logger.info("[MnesiaSync] Import complete: #{total_imported} records")

      {:ok, %{
        records: total_imported,
        tables: Map.new(results, fn {table, {:ok, count}} -> {table, count} end)
      }}
    end
  end

  @doc """
  Show info about an export file without importing.
  """
  def info(file_path) do
    binary = File.read!(file_path)
    export_data = :erlang.binary_to_term(binary)

    IO.puts("\n=== Mnesia Export Info ===")
    IO.puts("File: #{file_path}")
    IO.puts("Size: #{format_bytes(File.stat!(file_path).size)}")
    IO.puts("Version: #{export_data.version}")
    IO.puts("Exported at: #{format_timestamp(export_data.exported_at)}")
    IO.puts("Exported from: #{export_data.exported_from}")
    IO.puts("\nTables:")
    Enum.each(export_data.record_counts, fn {table, count} ->
      IO.puts("  #{table}: #{count} records")
    end)
    IO.puts("")

    export_data.record_counts
  end

  @doc """
  Compare local Mnesia with an export file.
  """
  def compare(file_path) do
    binary = File.read!(file_path)
    export_data = :erlang.binary_to_term(binary)

    IO.puts("\n=== Mnesia Comparison ===")
    IO.puts("Export from: #{format_timestamp(export_data.exported_at)}")
    IO.puts("")
    IO.puts("Table                  | Export | Local  | Diff")
    IO.puts("-----------------------+--------+--------+------")

    Enum.each(export_data.record_counts, fn {table, export_count} ->
      local_count = table_count(table)
      diff = local_count - export_count
      diff_str = cond do
        diff > 0 -> "+#{diff}"
        diff < 0 -> "#{diff}"
        true -> "="
      end
      IO.puts("#{String.pad_trailing(to_string(table), 22)} | #{String.pad_leading(to_string(export_count), 6)} | #{String.pad_leading(to_string(local_count), 6)} | #{diff_str}")
    end)
    IO.puts("")
  end

  # ===== Private Functions =====

  defp import_table(table, records, opts) when is_list(records) do
    mode = Keyword.get(opts, :mode, default_mode(table))

    # Clear table if replacing
    if mode == :replace do
      clear_table(table)
      Logger.info("[MnesiaSync] Cleared table #{table}")
    end

    # Write records
    count = Enum.reduce(records, 0, fn record, acc ->
      :mnesia.dirty_write(record)
      acc + 1
    end)

    Logger.info("[MnesiaSync] Imported #{count} records into #{table}")
    {:ok, count}
  end

  defp clear_table(table) do
    :mnesia.clear_table(table)
  rescue
    _ ->
      # If clear_table fails, delete records one by one
      :mnesia.activity(:async_dirty, fn ->
        :mnesia.foldl(fn record, _acc ->
          key = elem(record, 1)
          :mnesia.delete({table, key})
        end, :ok, table)
      end)
  end

  defp default_mode(table) do
    if table in @replace_tables, do: :replace, else: :merge
  end

  defp table_count(table) do
    :mnesia.table_info(table, :size)
  rescue
    _ -> 0
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_timestamp(unix_time) do
    DateTime.from_unix!(unix_time) |> DateTime.to_string()
  end
end
