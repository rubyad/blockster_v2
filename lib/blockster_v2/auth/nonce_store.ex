defmodule BlocksterV2.Auth.NonceStore do
  @moduledoc """
  ETS-based nonce store for SIWS authentication.
  Nonces expire after 5 minutes, cleanup runs every minute.
  """

  use GenServer

  @table :auth_nonces
  @ttl_ms :timer.minutes(5)
  @cleanup_interval_ms :timer.minutes(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def put(nonce, wallet_address) do
    :ets.insert(@table, {nonce, wallet_address, System.monotonic_time(:millisecond)})
    :ok
  end

  def take(nonce) do
    case :ets.take(@table, nonce) do
      [{^nonce, wallet_address, created_at}] ->
        now = System.monotonic_time(:millisecond)

        if now - created_at <= @ttl_ms do
          {:ok, wallet_address}
        else
          {:error, :expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now - @ttl_ms}], [true]}])
  end
end
