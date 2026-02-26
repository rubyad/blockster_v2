defmodule BlocksterV2.ProductionSafetyTest do
  @moduledoc """
  Guards against regressions that caused the Feb 25-26, 2026 production outage.
  See docs/outage-report-feb-2026.md for full incident report.

  These tests verify critical infrastructure configuration that, if broken,
  can cause silent crash-loops with zero error output.
  """
  use ExUnit.Case, async: true

  @project_root Path.join([__DIR__, "..", ".."])

  # ---------------------------------------------------------------------------
  # 1. Socket options must NEVER include :keepalive
  #    Root cause of the 33-hour outage: :keepalive + :inet6 kills Postgrex
  #    connections instantly (~49ms) on Fly.io's IPv6 internal network.
  # ---------------------------------------------------------------------------

  test "runtime.exs prod Repo config does not include :keepalive in socket_options" do
    runtime_exs = Path.join(@project_root, "config/runtime.exs") |> File.read!()

    # Must not contain :keepalive anywhere in socket_options
    refute runtime_exs =~ ~r/socket_options:.*:keepalive/,
           """
           CRITICAL: :keepalive found in socket_options in config/runtime.exs!
           This WILL kill IPv6 connections on Fly.io's internal network.
           See docs/outage-report-feb-2026.md — this caused a 33-hour outage.
           Use `socket_options: maybe_ipv6` without :keepalive.
           """
  end

  test "runtime.exs does not append :keepalive to socket_options list" do
    runtime_exs = Path.join(@project_root, "config/runtime.exs") |> File.read!()

    refute runtime_exs =~ ~r/\+\+\s*\[:keepalive\]/,
           """
           CRITICAL: Found `++ [:keepalive]` pattern in runtime.exs!
           This was the exact code that caused the Feb 2026 outage.
           """
  end

  # ---------------------------------------------------------------------------
  # 2. Dockerfile must include ERL_AFLAGS for IPv6 distribution
  #    Without this, the BEAM defaults to IPv4 for hostname resolution,
  #    which fails on Fly.io's IPv6-only internal network.
  # ---------------------------------------------------------------------------

  test "Dockerfile includes ERL_AFLAGS for IPv6 Erlang distribution" do
    dockerfile = Path.join(@project_root, "Dockerfile") |> File.read!()

    assert dockerfile =~ ~r/ERL_AFLAGS.*proto_dist.*inet6_tcp/,
           """
           CRITICAL: Dockerfile is missing ERL_AFLAGS="-proto_dist inet6_tcp"!
           Fly.io uses IPv6 internally. Without this flag, the BEAM defaults to
           IPv4 for distribution and Postgrex connections will fail.
           Add to the runner stage: ENV ERL_AFLAGS="-proto_dist inet6_tcp"
           """
  end

  # ---------------------------------------------------------------------------
  # 3. Application.start must ignore SIGUSR1
  #    Fly.io's init sends SIGUSR1 to child processes during deployment.
  #    The BEAM's default handler writes a crash dump and terminates.
  # ---------------------------------------------------------------------------

  test "Application.start ignores SIGUSR1 signal" do
    app_source = Path.join(@project_root, "lib/blockster_v2/application.ex") |> File.read!()

    assert app_source =~ ~r/:os\.set_signal\(:sigusr1,\s*:ignore\)/,
           """
           CRITICAL: Application.start is not ignoring SIGUSR1!
           Fly.io's init sends SIGUSR1 during deployment, which by default
           causes the BEAM to write a crash dump and exit.
           Add `:os.set_signal(:sigusr1, :ignore)` to Application.start/2.
           """
  end

  # ---------------------------------------------------------------------------
  # 4. Oban must use PG notifier (not Postgres)
  #    Oban.Notifiers.Postgres uses LISTEN/NOTIFY which is incompatible
  #    with PgBouncer transaction mode (used by Fly.io MPG).
  # ---------------------------------------------------------------------------

  test "Oban uses PG notifier (compatible with PgBouncer)" do
    oban_config = Application.get_env(:blockster_v2, Oban)

    assert oban_config[:notifier] == Oban.Notifiers.PG,
           """
           CRITICAL: Oban notifier is #{inspect(oban_config[:notifier])}, expected Oban.Notifiers.PG!
           Oban.Notifiers.Postgres uses LISTEN/NOTIFY which is incompatible with
           PgBouncer transaction mode. This causes Oban to crash-loop on Fly.io.
           Set `notifier: Oban.Notifiers.PG` in config/config.exs.
           """
  end

  test "Oban uses Global peer (compatible with PgBouncer)" do
    oban_config = Application.get_env(:blockster_v2, Oban)

    assert oban_config[:peer] == Oban.Peers.Global,
           """
           CRITICAL: Oban peer is #{inspect(oban_config[:peer])}, expected Oban.Peers.Global!
           The default Postgres-based peer is incompatible with PgBouncer transaction mode.
           Set `peer: Oban.Peers.Global` in config/config.exs.
           """
  end

  # ---------------------------------------------------------------------------
  # 5. MnesiaInitializer must not call :mnesia.stop() in init/join paths
  #    Stopping Mnesia destroys all ETS tables, crashing GenServers that
  #    depend on them (BuxBoosterBetSettler, PriceTracker, etc.).
  #    The only legitimate :mnesia.stop() is in migrate_from_old_node/1.
  # ---------------------------------------------------------------------------

  test "MnesiaInitializer does not call :mnesia.stop() outside of migration" do
    source = Path.join(@project_root, "lib/blockster_v2/mnesia_initializer.ex") |> File.read!()

    # Split into functions by finding `defp` boundaries
    # The ONLY function allowed to call :mnesia.stop() is migrate_from_old_node
    lines = String.split(source, "\n")

    mnesia_stop_locations =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} ->
        String.contains?(line, ":mnesia.stop()") and not String.starts_with?(String.trim(line), "#")
      end)
      |> Enum.map(fn {_line, idx} -> idx end)

    # Find which function each :mnesia.stop() call is in
    function_defs =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} -> line =~ ~r/^\s+def(p)?\s+\w+/ end)
      |> Enum.map(fn {line, idx} ->
        name = Regex.run(~r/def(p)?\s+(\w+)/, line) |> List.last()
        {idx, name}
      end)

    for stop_line <- mnesia_stop_locations do
      # Find the function this line belongs to (last defp before this line)
      {_fn_line, fn_name} =
        function_defs
        |> Enum.filter(fn {idx, _} -> idx <= stop_line end)
        |> List.last()

      assert fn_name == "migrate_from_old_node",
             """
             CRITICAL: :mnesia.stop() found at line #{stop_line} in function `#{fn_name}`!
             Only `migrate_from_old_node/1` is allowed to call :mnesia.stop().
             Stopping Mnesia in init/join paths destroys ETS tables and crashes
             dependent GenServers. Use `ensure_mnesia_running/0` instead.
             See docs/outage-report-feb-2026.md.
             """
    end
  end

  # ---------------------------------------------------------------------------
  # 6. fly.toml must have release_command for migrations
  #    Without this, schema migrations won't run on deploy.
  # ---------------------------------------------------------------------------

  test "fly.toml includes release_command for migrations" do
    fly_toml = Path.join(@project_root, "fly.toml") |> File.read!()

    assert fly_toml =~ ~r/release_command\s*=\s*'\/app\/bin\/migrate'/,
           """
           fly.toml is missing release_command = '/app/bin/migrate'!
           Without this, database migrations won't run on deploy.
           """
  end

  # ---------------------------------------------------------------------------
  # 7. fly.toml must have kill_signal = SIGTERM (not default SIGINT)
  #    SIGTERM gives the BEAM time for graceful shutdown.
  # ---------------------------------------------------------------------------

  test "fly.toml uses SIGTERM for graceful BEAM shutdown" do
    fly_toml = Path.join(@project_root, "fly.toml") |> File.read!()

    assert fly_toml =~ ~r/kill_signal\s*=\s*'SIGTERM'/,
           "fly.toml should use kill_signal = 'SIGTERM' for graceful BEAM shutdown"
  end
end
