defmodule Mix.Tasks.Mnesia.Export do
  @moduledoc """
  Export local Mnesia data to a file for syncing to production.

  ## Usage
      mix mnesia.export [file_path]

  Default file path: /tmp/hr_mnesia_export.etf
  """
  use Mix.Task

  @shortdoc "Export Mnesia data to file"

  def run(args) do
    file_path = List.first(args) || "/tmp/hr_mnesia_export.etf"

    Mix.Task.run("app.start")

    IO.puts("\n🔄 Exporting Mnesia data to #{file_path}...")

    case HighRollers.MnesiaSync.export_all(file_path) do
      {:ok, result} ->
        IO.puts("✅ Export complete!")
        IO.puts("   Records: #{result.records}")
        IO.puts("   Size: #{format_bytes(result.size)}")
        IO.puts("   File: #{result.file}")
        IO.puts("\nTo sync to production:")
        IO.puts("  1. flyctl ssh sftp shell -a high-rollers-elixir")
        IO.puts("  2. put #{file_path} /tmp/hr_mnesia_export.etf")
        IO.puts("  3. flyctl ssh console -a high-rollers-elixir -C '/app/bin/high_rollers remote'")
        IO.puts("  4. HighRollers.MnesiaSync.import_all(\"/tmp/hr_mnesia_export.etf\")")

      {:error, reason} ->
        IO.puts("❌ Export failed: #{inspect(reason)}")
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end

defmodule Mix.Tasks.Mnesia.Import do
  @moduledoc """
  Import Mnesia data from a file (for use in production).

  ## Usage
      mix mnesia.import [file_path] [--dry-run]

  Default file path: /tmp/hr_mnesia_export.etf
  """
  use Mix.Task

  @shortdoc "Import Mnesia data from file"

  def run(args) do
    {opts, args, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    file_path = List.first(args) || "/tmp/hr_mnesia_export.etf"
    dry_run = Keyword.get(opts, :dry_run, false)

    Mix.Task.run("app.start")

    IO.puts("\n🔄 Importing Mnesia data from #{file_path}#{if dry_run, do: " (DRY RUN)"}...")

    case HighRollers.MnesiaSync.import_all(file_path, dry_run: dry_run) do
      {:ok, result} ->
        if dry_run do
          IO.puts("📋 Would import:")
          Enum.each(result.tables, fn {table, count} ->
            IO.puts("   #{table}: #{count} records")
          end)
        else
          IO.puts("✅ Import complete!")
          IO.puts("   Records: #{result.records}")
        end

      {:error, reason} ->
        IO.puts("❌ Import failed: #{inspect(reason)}")
    end
  end
end

defmodule Mix.Tasks.Mnesia.Info do
  @moduledoc """
  Show info about a Mnesia export file.

  ## Usage
      mix mnesia.info [file_path]
  """
  use Mix.Task

  @shortdoc "Show info about Mnesia export file"

  def run(args) do
    file_path = List.first(args) || "/tmp/hr_mnesia_export.etf"

    if File.exists?(file_path) do
      HighRollers.MnesiaSync.info(file_path)
    else
      IO.puts("❌ File not found: #{file_path}")
    end
  end
end
