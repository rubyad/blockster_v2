defmodule BlocksterV2.TelegramBot.HourlyPromoScheduler do
  @moduledoc """
  Orchestrates hourly promo rotation for the Telegram group.
  GlobalSingleton — one instance across the cluster.

  Every hour:
  1. Settle the previous hour's promo (pay winners, clean up rules)
  2. Pick a new promo from weighted rotation
  3. Activate the promo (create custom rules, boost rates, etc.)
  4. Announce the new promo + previous results in Telegram
  5. Schedule next hour
  """
  use GenServer
  require Logger

  alias BlocksterV2.TelegramBot.{PromoEngine, TelegramGroupMessenger}
  alias BlocksterV2.Notifications.SystemConfig

  @doc false
  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @impl true
  def init(_opts) do
    schedule_next_promo()
    Logger.info("[HourlyPromoScheduler] Started, first promo scheduled")
    {:ok, %{current_promo: nil, history: [], promo_started_at: nil}}
  end

  # ======== Public API ========

  @doc "Get the current state (for admin dashboard)"
  def get_state do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  @doc "Force a specific promo category next hour"
  def force_next(category) when is_atom(category) do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.cast(pid, {:force_next, category})
    end
  end

  @doc "Trigger a promo cycle immediately (for testing/admin)"
  def run_now do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> send(pid, :run_promo)
    end
  end

  # ======== Callbacks ========

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      current_promo: state.current_promo && Map.take(state.current_promo, [:id, :name, :category, :started_at, :expires_at]),
      promo_started_at: state.promo_started_at,
      history: Enum.map(state.history, &Map.take(&1, [:id, :name, :category])) |> Enum.take(10),
      bot_enabled: SystemConfig.get("hourly_promo_enabled", true),
      budget_remaining: PromoEngine.remaining_budget(),
      daily_state: PromoEngine.get_daily_state()
    }
    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_cast({:force_next, category}, state) do
    {:noreply, Map.put(state, :forced_category, category)}
  end

  @impl true
  def handle_info(:run_promo, state) do
    if SystemConfig.get("hourly_promo_enabled", true) do
      run_promo_cycle(state)
    else
      # Bot is paused — clean up active rules and skip
      PromoEngine.cleanup_all_bot_rules()
      Logger.info("[HourlyPromoScheduler] Bot is paused, skipping this hour")
      schedule_next_promo()
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ======== Private ========

  defp run_promo_cycle(state) do
    if PromoEngine.budget_exhausted?() do
      TelegramGroupMessenger.send_update(
        "<b>📊 Daily Rewards Complete!</b>\n\nToday's BUX reward budget has been distributed!\nCome back tomorrow for fresh promos and giveaways!\n\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
      )
      Logger.info("[HourlyPromoScheduler] Daily budget exhausted, skipping promo")
      schedule_next_promo()
      {:noreply, state}
    else
      # 1. Settle previous promo
      previous_results = settle_previous(state.current_promo)

      # 2. Pick next promo (respect forced category if set)
      promo = case Map.get(state, :forced_category) do
        nil -> PromoEngine.pick_next_promo(state.history)
        category ->
          # Force a specific category but still use random template within it
          promo = PromoEngine.pick_next_promo(state.history)
          if promo.category != category do
            # Re-pick with forced category
            PromoEngine.pick_next_promo([])
            |> then(fn p ->
              templates = PromoEngine.all_templates()[category] || []
              if length(templates) > 0 do
                template = Enum.random(templates)
                %{p | category: category, template: template, name: template.name,
                  announcement_html: Map.get(template, :announcement) || p.announcement_html}
              else
                p
              end
            end)
          else
            promo
          end
      end

      # 3. Activate the promo
      PromoEngine.activate_promo(promo)

      # 4. Announce in group
      TelegramGroupMessenger.announce_promo(promo)

      # 5. Announce previous results if any
      if state.current_promo do
        settled_promo = %{state.current_promo | results: previous_results}
        results_html = PromoEngine.format_results_html(settled_promo, promo)
        if results_html, do: TelegramGroupMessenger.announce_results(results_html)
      end

      # 6. Save state to Mnesia for crash recovery
      save_state(promo, state.history)

      # 7. Schedule next
      schedule_next_promo()

      Logger.info("[HourlyPromoScheduler] Running promo: #{promo.name} (#{promo.category})")

      {:noreply, %{state |
        current_promo: promo,
        history: [promo | Enum.take(state.history, 23)],
        promo_started_at: DateTime.utc_now(),
        forced_category: nil
      }}
    end
  end

  defp settle_previous(nil), do: nil
  defp settle_previous(promo) do
    try do
      PromoEngine.settle_promo(promo)
    rescue
      e ->
        Logger.error("[HourlyPromoScheduler] Error settling promo #{promo.name}: #{inspect(e)}")
        nil
    end
  end

  defp schedule_next_promo do
    now = DateTime.utc_now()
    unix = DateTime.to_unix(now)
    seconds_until_next = 3600 - rem(unix, 3600)
    delay_ms = max(seconds_until_next * 1000, 1000)
    Process.send_after(self(), :run_promo, delay_ms)
  end

  defp save_state(promo, history) do
    try do
      serializable_promo = %{
        id: promo.id,
        name: promo.name,
        category: promo.category,
        started_at: promo.started_at,
        expires_at: promo.expires_at
      }
      serializable_history = Enum.map(history, fn h ->
        %{id: h.id, name: h.name, category: h.category}
      end) |> Enum.take(24)

      :mnesia.dirty_write({:hourly_promo_state, :current, serializable_promo, DateTime.utc_now(), serializable_history})
    rescue
      _ -> :ok
    end
  end
end
