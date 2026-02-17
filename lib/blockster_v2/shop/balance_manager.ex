defmodule BlocksterV2.Shop.BalanceManager do
  @moduledoc """
  Serialized GenServer for BUX balance deductions during shop checkout.
  Prevents concurrent double-spend across multiple browser tabs by routing
  all BUX deductions through a single global process.
  """

  use GenServer
  alias BlocksterV2.EngagementTracker

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, %{}) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  @doc "Atomically deduct BUX for a checkout. Returns {:ok, new_balance} or {:error, :insufficient, balance}"
  def deduct_bux(user_id, amount) do
    GenServer.call({:global, __MODULE__}, {:deduct_bux, user_id, amount}, 10_000)
  end

  @doc "Credit BUX back (e.g. on payment failure)"
  def credit_bux(user_id, amount) do
    GenServer.call({:global, __MODULE__}, {:credit_bux, user_id, amount}, 10_000)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:deduct_bux, user_id, amount}, _from, state) do
    case EngagementTracker.get_user_bux_balance(user_id) do
      balance when balance >= amount ->
        EngagementTracker.deduct_user_token_balance(user_id, nil, "BUX", amount)
        {:reply, {:ok, balance - amount}, state}

      balance ->
        {:reply, {:error, :insufficient, balance}, state}
    end
  end

  @impl true
  def handle_call({:credit_bux, user_id, amount}, _from, state) do
    EngagementTracker.credit_user_token_balance(user_id, nil, "BUX", amount)
    {:reply, :ok, state}
  end
end
