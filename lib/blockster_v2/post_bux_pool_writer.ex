defmodule BlocksterV2.PostBuxPoolWriter do
  @moduledoc """
  Serialized GenServer for writing to the post_bux_points Mnesia table.

  This GenServer ensures that all pool operations (deposits and deductions) are
  serialized to prevent race conditions when multiple users drain the pool simultaneously.

  Without serialization, dirty Mnesia operations could over-distribute BUX when
  multiple users read the same balance before any write completes.

  IMPORTANT: Uses GlobalSingleton for cluster-wide serialization. Only one instance
  runs across all nodes, ensuring pool operations are serialized even when users
  connect to different nodes.

  ## Usage

  Instead of calling `EngagementTracker.try_deduct_from_pool/2` directly,
  call `PostBuxPoolWriter.try_deduct_from_pool/2` which routes through this GenServer.

  Deposits are less time-sensitive but also serialized for consistency.
  """
  use GenServer
  require Logger

  alias BlocksterV2.EngagementTracker

  # Client API

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        # Notify the process that it's the globally registered instance
        send(pid, :registered)
        {:ok, pid}
      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc """
  Deposits BUX into a post's pool. Serialized through GenServer.
  Returns {:ok, new_balance} or {:error, reason}.
  """
  def deposit(post_id, amount) when is_integer(amount) and amount > 0 do
    GenServer.call({:global, __MODULE__}, {:deposit, post_id, amount}, 10_000)
  end

  @doc """
  Attempts to deduct BUX from post's pool. Serialized through GenServer.
  Returns {:ok, amount, status} where status is :full_amount, :partial_amount, :pool_empty, or :no_pool.
  """
  def try_deduct(post_id, requested_amount) when is_number(requested_amount) and requested_amount > 0 do
    GenServer.call({:global, __MODULE__}, {:deduct, post_id, requested_amount}, 10_000)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Don't log here - wait for :registered message to confirm we're the global instance
    {:ok, %{registered: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[PostBuxPoolWriter] Started - serializing pool operations")
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:deposit, post_id, amount}, _from, state) do
    result = do_deposit(post_id, amount)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:deduct, post_id, requested_amount}, _from, state) do
    result = do_deduct(post_id, requested_amount)
    {:reply, result, state}
  end

  # Private Functions - actual Mnesia operations

  defp do_deposit(post_id, amount) do
    now = System.system_time(:second)

    result = case :mnesia.dirty_read({:post_bux_points, post_id}) do
      [] ->
        # Create new record
        record = {
          :post_bux_points,
          post_id,
          nil,     # reward
          nil,     # read_time
          amount,  # bux_balance (pool)
          amount,  # bux_deposited (lifetime)
          0,       # total_distributed
          nil,     # extra_field2
          nil,     # extra_field3
          nil,     # extra_field4
          now,     # created_at
          now      # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[PostBuxPoolWriter] Created pool for post #{post_id}: balance=#{amount}")
        {:ok, amount}

      [existing] ->
        current_balance = elem(existing, 4) || 0
        current_deposited = elem(existing, 5) || 0
        new_balance = current_balance + amount
        new_deposited = current_deposited + amount

        updated = existing
          |> put_elem(4, new_balance)     # bux_balance
          |> put_elem(5, new_deposited)   # bux_deposited
          |> put_elem(11, now)            # updated_at

        :mnesia.dirty_write(updated)
        Logger.info("[PostBuxPoolWriter] Deposited #{amount} to post #{post_id}: balance=#{new_balance}")
        {:ok, new_balance}
    end

    # Broadcast the BUX balance update
    case result do
      {:ok, new_balance} ->
        EngagementTracker.broadcast_bux_update(post_id, new_balance)
        result
      _ ->
        result
    end
  rescue
    e ->
      Logger.error("[PostBuxPoolWriter] Error depositing post bux: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[PostBuxPoolWriter] Exit depositing post bux: #{inspect(e)}")
      {:error, e}
  end

  defp do_deduct(post_id, requested_amount) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:post_bux_points, post_id}) do
      [] ->
        # No pool exists for this post
        {:ok, 0, :no_pool}

      [record] ->
        pool_balance = elem(record, 4) || 0

        cond do
          pool_balance <= 0 ->
            {:ok, 0, :pool_empty}

          pool_balance >= requested_amount ->
            # Full amount available - deduct it
            new_balance = pool_balance - requested_amount
            total_distributed = (elem(record, 6) || 0) + requested_amount

            updated = record
              |> put_elem(4, new_balance)
              |> put_elem(6, total_distributed)
              |> put_elem(11, now)

            :mnesia.dirty_write(updated)
            EngagementTracker.broadcast_bux_update(post_id, new_balance)
            {:ok, requested_amount, :full_amount}

          true ->
            # Partial amount available - deduct whatever remains
            awarded = pool_balance
            total_distributed = (elem(record, 6) || 0) + awarded

            updated = record
              |> put_elem(4, 0)
              |> put_elem(6, total_distributed)
              |> put_elem(11, now)

            :mnesia.dirty_write(updated)
            EngagementTracker.broadcast_bux_update(post_id, 0)
            {:ok, awarded, :partial_amount}
        end
    end
  rescue
    e ->
      Logger.error("[PostBuxPoolWriter] Error deducting from pool: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[PostBuxPoolWriter] Exit deducting from pool: #{inspect(e)}")
      {:error, e}
  end
end
