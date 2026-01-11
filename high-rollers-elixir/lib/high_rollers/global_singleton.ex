defmodule HighRollers.GlobalSingleton do
  @moduledoc """
  Provides safe global GenServer registration for rolling deploys.

  Problem: When using raw `{:global, Name}` registration, Erlang's default behavior
  during name conflicts is to kill one of the processes. This causes crashes during
  rolling deploys when a new node tries to register a global name that already
  exists on another node.

  Solution: Custom conflict resolver that keeps existing process, rejects new one.
  Uses distributed Process.alive? check via RPC for remote PIDs.

  Usage:
  ```elixir
  def start_link(opts) do
    case HighRollers.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end
  ```
  """
  require Logger

  @doc """
  Starts a GenServer with global registration using a custom conflict resolver.

  Returns:
  - `{:ok, pid}` - Successfully started and registered
  - `{:already_registered, pid}` - Another node is running this GenServer
  """
  def start_link(module, opts) do
    # Check if already running globally
    case :global.whereis_name(module) do
      :undefined ->
        # Not running, try to start
        case GenServer.start_link(module, opts, name: {:via, :global, {module, &resolve_conflict/3}}) do
          {:ok, pid} ->
            Logger.info("[GlobalSingleton] Started #{inspect(module)} on #{node()}")
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            # Race condition - another node registered between our check and start
            Logger.info("[GlobalSingleton] #{inspect(module)} already started on #{node(pid)}")
            {:already_registered, pid}

          {:error, reason} ->
            {:error, reason}
        end

      pid ->
        # Already running somewhere
        if process_alive_distributed?(pid) do
          Logger.info("[GlobalSingleton] #{inspect(module)} already running on #{node(pid)}")
          {:already_registered, pid}
        else
          # Dead process, unregister and try again
          Logger.info("[GlobalSingleton] #{inspect(module)} was dead, unregistering")
          :global.unregister_name(module)
          start_link(module, opts)
        end
    end
  end

  @doc """
  Custom conflict resolver for :global registration.
  Keeps the first (existing) process, rejects the second.
  """
  def resolve_conflict(name, pid1, pid2) do
    Logger.info("[GlobalSingleton] Name conflict for #{inspect(name)}: keeping #{inspect(pid1)} on #{node(pid1)}, rejecting #{inspect(pid2)} on #{node(pid2)}")
    pid1
  end

  # Process.alive?/1 only works for local PIDs
  # For remote PIDs, we need to use RPC
  defp process_alive_distributed?(pid) do
    if node(pid) == node() do
      Process.alive?(pid)
    else
      case :rpc.call(node(pid), Process, :alive?, [pid], 5000) do
        true -> true
        false -> false
        {:badrpc, _} -> false  # Node unreachable
      end
    end
  end
end
