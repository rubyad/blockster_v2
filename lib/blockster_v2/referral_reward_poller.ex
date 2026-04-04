defmodule BlocksterV2.ReferralRewardPoller do
  @moduledoc """
  EVM event polling for referral rewards — DISABLED in Solana migration (Phase 9).

  Previously polled Rogue Chain for ReferralRewardPaid events from BuxBoosterGame
  and ROGUEBankroll. With the Solana migration, referral rewards are now minted
  directly by the settler service, so EVM polling is no longer needed.

  The GenServer structure is preserved so it can be repurposed for Solana event
  polling if needed in the future.
  """
  use GenServer
  require Logger

  # ----- Public API -----

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc """
  Backfill is a no-op — EVM polling disabled for Solana migration.
  """
  def backfill_from_block(_from_block) do
    {:ok, :evm_polling_disabled}
  end

  @doc """
  Get the current poller state (for debugging).
  """
  def get_state do
    GenServer.call({:global, __MODULE__}, :get_state)
  end

  # ----- GenServer Callbacks -----

  @impl true
  def init(_opts) do
    Logger.info("[ReferralRewardPoller] Starting (EVM polling disabled — Solana migration)")

    {:ok, %{
      last_block: nil,
      polling: false,
      initialized: false,
      disabled: true
    }}
  end

  @impl true
  def handle_info(:poll, state) do
    # EVM polling disabled — no-op
    {:noreply, state}
  end

  @impl true
  def handle_info(:wait_for_mnesia, state) do
    # EVM polling disabled — no-op
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:backfill, _from_block}, state) do
    # EVM polling disabled — no-op
    {:noreply, state}
  end
end
