defmodule BlocksterV2.Orders.OrderExpiryWorker do
  @moduledoc """
  Global singleton that expires stale unpaid orders after 30 minutes.
  Checks every 5 minutes.

  - pending/bux_pending/rogue_pending: expired with simple note
  - bux_paid/rogue_paid: expired and flagged for manual refund review
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.Order

  @check_interval :timer.minutes(5)
  @ttl_minutes 30

  @simple_expire_statuses ["pending", "bux_pending", "rogue_pending"]
  @partial_payment_statuses ["bux_paid", "rogue_paid"]

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
    expire_stale_orders()
    schedule()
    {:noreply, state}
  end

  @doc "Expire stale orders. Can be called directly for testing."
  def expire_stale_orders do
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_minutes, :minute)

    stale =
      from(o in Order,
        where: o.status in ^(@simple_expire_statuses ++ @partial_payment_statuses),
        where: o.inserted_at <= ^cutoff
      )
      |> Repo.all()

    if length(stale) > 0 do
      Logger.info("[OrderExpiryWorker] Expiring #{length(stale)} stale orders")
    end

    Enum.each(stale, fn order ->
      note =
        if order.status in @partial_payment_statuses,
          do: "Partial payment received (#{order.status}) — review for refund",
          else: "Auto-expired after #{@ttl_minutes} minutes"

      order
      |> Order.status_changeset(%{status: "expired", notes: note})
      |> Repo.update()
    end)

    length(stale)
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
