defmodule BlocksterV2.GlobalSingleton do
  @moduledoc """
  Helper module for registering global singleton GenServers with a custom
  conflict resolution strategy that doesn't kill running processes.

  When using {:global, Name} directly, Erlang's default behavior during a
  name conflict is to kill one of the processes. This can cause issues during
  rolling deploys when a joining node registers the same global name.

  This module provides a custom resolver that keeps the existing process
  running and returns :ignore for the new one, preventing crashes during
  Mnesia table synchronization.
  """

  require Logger

  @doc """
  Starts a GenServer with global registration using a custom conflict resolver.

  If a process is already registered globally with this name, returns {:ok, existing_pid}
  instead of causing a conflict. The calling GenServer should return :ignore when this
  returns {:already_registered, pid}.

  ## Examples

      def start_link(opts) do
        case GlobalSingleton.start_link(__MODULE__, opts) do
          {:ok, pid} -> {:ok, pid}
          {:already_registered, _pid} -> :ignore
        end
      end
  """
  def start_link(module, opts) do
    # Sync global name registry with other nodes before checking
    # This prevents race conditions during cluster formation where
    # whereis_name returns :undefined even though another node has registered
    :global.sync()

    case :global.whereis_name(module) do
      :undefined ->
        # No existing process, try to register
        do_start_link(module, opts)

      existing_pid ->
        # Process already exists globally - check if it's alive
        # Use RPC for remote PIDs since Process.alive?/1 only works locally
        if process_alive_distributed?(existing_pid) do
          Logger.info("[GlobalSingleton] #{inspect(module)} already running on #{node(existing_pid)}")
          {:already_registered, existing_pid}
        else
          # Existing pid is dead, unregister and start fresh
          :global.unregister_name(module)
          do_start_link(module, opts)
        end
    end
  end

  # Check if a process is alive, handling both local and remote PIDs
  defp process_alive_distributed?(pid) do
    if node(pid) == node() do
      # Local process - use Process.alive?
      Process.alive?(pid)
    else
      # Remote process - use RPC to check on the remote node
      case :rpc.call(node(pid), Process, :alive?, [pid], 5000) do
        true -> true
        false -> false
        {:badrpc, _} -> false  # Node unreachable, assume process is dead
      end
    end
  end

  defp do_start_link(module, opts) do
    # Start with a temporary name first
    case GenServer.start_link(module, opts) do
      {:ok, pid} ->
        # Now try to register globally with custom resolver
        Logger.info("[GlobalSingleton] #{inspect(module)} attempting registration for #{inspect(pid)}")
        case :global.register_name(module, pid, &resolve_conflict/3) do
          :yes ->
            Logger.info("[GlobalSingleton] #{inspect(module)} registration succeeded for #{inspect(pid)}")
            {:ok, pid}

          :no ->
            # Another process registered first, stop ours
            Logger.info("[GlobalSingleton] #{inspect(module)} registration failed for #{inspect(pid)}, stopping")
            GenServer.stop(pid, :normal)
            case :global.whereis_name(module) do
              :undefined -> {:error, :registration_failed}
              existing_pid -> {:already_registered, existing_pid}
            end
        end

      error ->
        error
    end
  end

  @doc """
  Custom conflict resolver for global name registration.

  When a name conflict is detected, this keeps the first registered process (pid1)
  and returns that pid. The second process (pid2) will not be killed - the caller
  must handle the :no return from register_name.

  This is safer than the default resolver which kills one of the processes,
  potentially interrupting in-flight operations like Mnesia table copying.
  """
  def resolve_conflict(name, pid1, pid2) do
    node1 = node(pid1)
    node2 = node(pid2)

    Logger.info(
      "[GlobalSingleton] Name conflict for #{inspect(name)}: " <>
        "keeping #{inspect(pid1)} on #{node1}, " <>
        "rejecting #{inspect(pid2)} on #{node2}"
    )

    # Return the first (existing) pid - don't kill either process
    pid1
  end
end
