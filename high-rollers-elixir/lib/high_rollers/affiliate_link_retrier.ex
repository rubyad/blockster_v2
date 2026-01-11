defmodule HighRollers.AffiliateLinkRetrier do
  @moduledoc """
  Periodically retries failed on-chain affiliate links.

  Runs every 5 minutes and queues any pending links to AdminTxQueue.
  """
  use GenServer
  require Logger

  @retry_interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first check after 1 minute (give system time to start up)
    Process.send_after(self(), :retry_pending_links, :timer.minutes(1))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:retry_pending_links, state) do
    retry_pending_links()
    schedule_next_retry()
    {:noreply, state}
  end

  defp retry_pending_links do
    pending = HighRollers.Users.get_pending_onchain_links()

    if length(pending) > 0 do
      Logger.info("[AffiliateLinkRetrier] Found #{length(pending)} pending on-chain links, queuing for retry")

      Enum.each(pending, fn %{buyer: buyer, affiliate: affiliate} ->
        HighRollers.AdminTxQueue.enqueue_link_affiliate(buyer, affiliate)
      end)
    end
  end

  defp schedule_next_retry do
    Process.send_after(self(), :retry_pending_links, @retry_interval)
  end
end
