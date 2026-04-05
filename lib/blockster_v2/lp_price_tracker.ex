defmodule BlocksterV2.LpPriceTracker do
  @moduledoc """
  Background worker that records LP price snapshots every 60 seconds.
  Runs as a GlobalSingleton so only one instance runs across the cluster.
  Fetches pool stats from the settler and stores price history in Mnesia.
  Prunes entries older than 30 days once per day.
  """

  use GenServer
  require Logger

  alias BlocksterV2.BuxMinter
  alias BlocksterV2.LpPriceHistory

  @interval :timer.seconds(60)
  @prune_interval :timer.hours(24)

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  def init(_) do
    {:ok, %{registered: false}}
  end

  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[LpPriceTracker] Started — recording LP prices every 60s")
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "pool:settlements")
    schedule()
    schedule_prune()
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state), do: {:noreply, state}

  def handle_info(:record_prices, state) do
    record_prices()
    schedule()
    {:noreply, state}
  end

  def handle_info({:bet_settled, vault_type}, state) do
    record_price_for_vault(vault_type)
    {:noreply, state}
  end

  def handle_info(:prune, state) do
    LpPriceHistory.prune()
    schedule_prune()
    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :record_prices, @interval)
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval)
  end

  defp record_prices do
    case BuxMinter.get_pool_stats() do
      {:ok, stats} ->
        for vault_type <- ["sol", "bux"] do
          case stats[vault_type] do
            %{"lpPrice" => price} when is_number(price) and price > 0 ->
              LpPriceHistory.record(vault_type, price)

            _ ->
              :skip
          end
        end

      {:error, _} ->
        :skip
    end
  rescue
    e -> Logger.warning("[LpPriceTracker] Error recording prices: #{inspect(e)}")
  end

  # Fetch fresh LP price for a single vault after bet settlement
  defp record_price_for_vault(vault_type) do
    case BuxMinter.get_pool_stats() do
      {:ok, stats} ->
        case stats[vault_type] do
          %{"lpPrice" => price} when is_number(price) and price > 0 ->
            LpPriceHistory.record(vault_type, price, force: true)

          _ ->
            :skip
        end

      {:error, _} ->
        :skip
    end
  rescue
    e -> Logger.warning("[LpPriceTracker] Error recording post-settlement price: #{inspect(e)}")
  end
end
