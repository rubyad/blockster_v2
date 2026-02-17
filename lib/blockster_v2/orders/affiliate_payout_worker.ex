defmodule BlocksterV2.Orders.AffiliatePayoutWorker do
  @moduledoc """
  Global singleton that processes held affiliate payouts past their chargeback
  hold date. Runs hourly.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.AffiliatePayout

  @check_interval :timer.hours(1)

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  @impl true
  def init(_) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    now = DateTime.utc_now()

    payouts =
      from(p in AffiliatePayout,
        where: p.status == "held",
        where: p.held_until <= ^now,
        preload: [:order, :referrer]
      )
      |> Repo.all()

    if length(payouts) > 0 do
      Logger.info("[AffiliatePayoutWorker] Processing #{length(payouts)} held payouts")
    end

    Enum.each(payouts, fn p ->
      case BlocksterV2.Orders.execute_affiliate_payout(p) do
        {:ok, _} ->
          Logger.info("[AffiliatePayoutWorker] Paid #{p.id}")

        {:error, r} ->
          Logger.error("[AffiliatePayoutWorker] Failed #{p.id}: #{inspect(r)}")

          p
          |> Ecto.Changeset.change(%{status: "failed", failure_reason: "#{inspect(r)}"})
          |> Repo.update()
      end
    end)

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
