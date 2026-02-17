defmodule BlocksterV2.Orders.OrderExpiryWorker do
  @moduledoc """
  Global singleton that cancels unpaid orders after 30 minutes.
  Checks every 5 minutes.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.Order

  @check_interval :timer.minutes(5)
  @ttl_minutes 30

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
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_minutes, :minute)

    stale =
      from(o in Order,
        where: o.status in ["pending", "bux_paid", "rogue_paid", "helio_pending"],
        where: o.inserted_at <= ^cutoff
      )
      |> Repo.all()

    if length(stale) > 0 do
      Logger.info("[OrderExpiryWorker] Expiring #{length(stale)} stale orders")
    end

    Enum.each(stale, fn order ->
      note =
        if order.status in ["bux_paid", "rogue_paid", "helio_pending"],
          do: "Auto-expired with partial payment (#{order.status}). Needs manual refund review.",
          else: "Auto-expired after #{@ttl_minutes}m"

      order
      |> Order.status_changeset(%{status: "cancelled", notes: note})
      |> Repo.update()
    end)

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
