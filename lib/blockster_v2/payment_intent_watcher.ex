defmodule BlocksterV2.PaymentIntentWatcher do
  @moduledoc """
  Polls the settler every few seconds for the funding status of every open
  shop payment intent. When the settler reports `funded`, we mark the intent
  + order paid and kick off a sweep to treasury.

  GlobalSingleton so only one node polls (matches the pattern used by the
  other cluster-wide schedulers).
  """

  use GenServer
  require Logger

  alias BlocksterV2.{PaymentIntents, Repo, SettlerClient}
  alias BlocksterV2.Orders.PaymentIntent

  import Ecto.Query

  # SOL payment intents have a 15-min TTL, and users stick around on the
  # checkout page while they wait for confirmation — 30s polling gives ~30
  # chances to catch a funding event per intent, more than enough. The
  # watcher also short-circuits below when zero intents are open, so idle
  # periods cost one cheap existence query per tick instead of two full
  # table scans.
  @poll_interval_ms :timer.seconds(30)

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, pid} ->
        {:ok, pid}
    end
  end

  def init_with_options(_opts) do
    Logger.info("[PaymentIntentWatcher] init")
    {:ok, %{timer: nil, registered: false}}
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(opts), do: init_with_options(opts)

  @impl true
  def handle_info(:registered, state) do
    timer = Process.send_after(self(), :tick, @poll_interval_ms)
    {:noreply, %{state | timer: timer, registered: true}}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_once()
    timer = Process.send_after(self(), :tick, @poll_interval_ms)
    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Tick logic ──────────────────────────────────────────────────────────────

  @doc false
  def tick_once do
    # Short-circuit when there's nothing to do — one cheap `EXISTS` query
    # instead of two full-table SELECTs. In steady state (no active shop
    # checkouts) the watcher's DB footprint is a single LIMIT 1 query per
    # tick.
    if any_open_intents?() do
      check_pending()
      sweep_funded()
    end
  rescue
    e ->
      Logger.error("[PaymentIntentWatcher] tick failed: #{Exception.message(e)}")
  end

  defp any_open_intents? do
    Repo.exists?(from i in PaymentIntent, where: i.status in ["pending", "funded"])
  end

  defp check_pending do
    PaymentIntents.list_pending()
    |> Enum.each(&check_one/1)
  end

  defp check_one(%PaymentIntent{} = intent) do
    cond do
      PaymentIntents.expired?(intent) ->
        PaymentIntents.mark_expired(intent.id)

      true ->
        case SettlerClient.intent_status(intent.pubkey, intent.expected_lamports) do
          {:ok, %{"funded" => true} = resp} ->
            PaymentIntents.mark_funded(
              intent.id,
              resp["funded_tx_sig"],
              resp["balance_lamports"] || intent.expected_lamports
            )

          {:ok, _not_yet} ->
            PaymentIntents.mark_checked(intent.id)

          {:error, reason} ->
            Logger.warning(
              "[PaymentIntentWatcher] status check failed for #{intent.pubkey}: #{inspect(reason)}"
            )
        end
    end
  end

  defp sweep_funded do
    PaymentIntents.list_fundings_to_sweep()
    |> Enum.each(&sweep_one/1)
  end

  defp sweep_one(%PaymentIntent{} = intent) do
    case SettlerClient.sweep_intent(intent.pubkey, intent.order_id) do
      {:ok, %{tx_sig: sig}} ->
        PaymentIntents.mark_swept(intent.id, sig)

      {:error, reason} ->
        Logger.warning(
          "[PaymentIntentWatcher] sweep failed for #{intent.pubkey}: #{inspect(reason)}"
        )
    end
  end
end
