defmodule BlocksterV2.Orders.BuxBurnWatcher do
  @moduledoc """
  Global singleton that surfaces orders stuck in `bux_pending` past the 15-min
  SOL payment-intent window (SHOP-14). The 15-min mark is where the on-chain
  BUX burn is effectively forfeited — the matching SOL intent has expired, so
  the user can't complete the order without admin intervention.

  Behaviour:
    * Tick every 60s.
    * Selects orders with `status == "bux_pending"`, `bux_burn_started_at`
      set, timestamp older than 15 min, and `bux_burn_tx_hash` still nil
      (i.e. the JS hook never reported the burn sig — SHOP-15's stuck UI).
    * Logs each one at :warning and broadcasts `{:stuck_bux_order, order_id}`
      on the `"admin:stuck_bux"` PubSub topic so a future admin LV can pick
      them up without its own poll loop.

  Does NOT mutate order state. The existing `OrderExpiryWorker` (30-min TTL)
  still owns the transition to `:expired`. This watcher surfaces the stuck
  window; the admin decides whether to refund via goodwill.

  Business logic is `run_once/0` — pure call that returns the list of stuck
  orders — so tests can assert without driving the GenServer scheduler.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.Order

  @check_interval :timer.seconds(60)
  @stuck_after_minutes 15

  @topic "admin:stuck_bux"

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  def topic, do: @topic

  @impl true
  def init(_) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    run_once()
    schedule()
    {:noreply, state}
  end

  @doc """
  One pass over the orders table. Returns the list of stuck orders so tests
  can assert on it. Logs + broadcasts as a side effect.
  """
  def run_once(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@stuck_after_minutes, :minute)

    stuck =
      from(o in Order,
        where: o.status == "bux_pending",
        where: not is_nil(o.bux_burn_started_at),
        where: o.bux_burn_started_at <= ^cutoff,
        where: is_nil(o.bux_burn_tx_hash)
      )
      |> Repo.all()

    Enum.each(stuck, &report/1)
    stuck
  end

  defp report(%Order{} = order) do
    elapsed =
      order.bux_burn_started_at
      |> DateTime.diff(DateTime.utc_now(), :minute)
      |> abs()

    Logger.warning(
      "[BuxBurnWatcher] order=#{order.id} user=#{order.user_id} bux=#{order.bux_tokens_burned} elapsed=#{elapsed}min — stuck in :bux_pending past #{@stuck_after_minutes}min window"
    )

    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, @topic, {:stuck_bux_order, order.id})
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
