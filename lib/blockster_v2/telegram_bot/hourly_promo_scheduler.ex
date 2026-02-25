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
    timer_ref = schedule_next_promo(nil)
    state = restore_state_from_mnesia()

    # If Mnesia table wasn't ready yet (MnesiaInitializer creates it later), retry after delay
    state = if is_nil(state.current_promo) do
      Process.send_after(self(), :retry_mnesia_restore, 5_000)
      state
    else
      Logger.info("[HourlyPromoScheduler] Restored state from Mnesia: #{state.current_promo.name}")
      state
    end

    Logger.info("[HourlyPromoScheduler] Started, first promo scheduled")
    {:ok, Map.put(state, :timer_ref, timer_ref)}
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
      pid -> GenServer.cast(pid, :run_now)
    end
  end

  # ======== Callbacks ========

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      current_promo: state.current_promo && Map.take(state.current_promo, [:id, :name, :category, :started_at, :expires_at]),
      promo_started_at: state.promo_started_at,
      history: Enum.map(state.history, &Map.take(&1, [:id, :name, :category, :started_at, :expires_at])) |> Enum.take(10)
    }
    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_cast({:force_next, category}, state) do
    {:noreply, Map.put(state, :forced_category, category)}
  end

  def handle_cast(:run_now, state) do
    if SystemConfig.get("hourly_promo_enabled", false) do
      run_promo_cycle(state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:run_promo, state) do
    if SystemConfig.get("hourly_promo_enabled", false) do
      run_promo_cycle(state)
    else
      Logger.info("[HourlyPromoScheduler] Bot is paused, skipping this hour")
      timer_ref = schedule_next_promo(state.timer_ref)
      {:noreply, %{state | timer_ref: timer_ref}}
    end
  end

  def handle_info(:retry_mnesia_restore, %{current_promo: nil} = state) do
    restored = restore_state_from_mnesia()
    if restored.current_promo do
      Logger.info("[HourlyPromoScheduler] Restored state from Mnesia (retry): #{restored.current_promo.name}")
      {:noreply, Map.merge(state, restored)}
    else
      Logger.info("[HourlyPromoScheduler] No promo state found in Mnesia")
      {:noreply, state}
    end
  end

  def handle_info(:retry_mnesia_restore, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # ======== Private ========

  defp run_promo_cycle(state) do
    if PromoEngine.budget_exhausted?() do
      Task.start(fn ->
        TelegramGroupMessenger.send_update(
          "<b>📊 Daily Rewards Complete!</b>\n\nToday's BUX reward budget has been distributed!\nCome back tomorrow for fresh promos and giveaways!\n\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
        )
      end)
      Logger.info("[HourlyPromoScheduler] Daily budget exhausted, skipping promo")
      timer_ref = schedule_next_promo(state.timer_ref)
      {:noreply, %{state | timer_ref: timer_ref}}
    else
      # 1. Settle previous promo SYNCHRONOUSLY (ensures payouts happen reliably)
      previous_promo = state.current_promo
      settled_promo = settle_previous_sync(previous_promo)

      # 2. Pick next promo (respect forced category if set)
      promo = case Map.get(state, :forced_category) do
        nil -> PromoEngine.pick_next_promo(state.history)
        category ->
          promo = PromoEngine.pick_next_promo(state.history)
          if promo.category != category do
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

      # 3. Activate the promo (fast — just writes to SystemConfig)
      PromoEngine.activate_promo(promo)

      # 4. Schedule next (cancel any existing timer first)
      timer_ref = schedule_next_promo(state.timer_ref)

      # 5. Update state
      new_state = %{state |
        current_promo: promo,
        history: [promo | Enum.take(state.history, 23)],
        promo_started_at: DateTime.utc_now(),
        forced_category: nil,
        timer_ref: timer_ref
      }

      # 6. Save state to Mnesia SYNCHRONOUSLY (survives node restart)
      save_state(promo, new_state.history)

      # 7. Telegram API calls in Task (slow, fire-and-forget is OK for messages)
      Task.start(fn ->
        try do
          case TelegramGroupMessenger.announce_promo(promo) do
            {:ok, %{body: %{"ok" => true}}} ->
              Logger.info("[HourlyPromoScheduler] Telegram announcement sent for #{promo.name}")

            {:ok, %{body: body}} ->
              Logger.error("[HourlyPromoScheduler] Telegram announce rejected: #{inspect(body)}")

            {:error, reason} ->
              Logger.error("[HourlyPromoScheduler] Telegram announce request failed: #{inspect(reason)}")
          end

          if settled_promo do
            results_html = PromoEngine.format_results_html(settled_promo, promo)
            if results_html do
              case TelegramGroupMessenger.announce_results(results_html) do
                {:ok, %{body: %{"ok" => true}}} ->
                  Logger.info("[HourlyPromoScheduler] Telegram results sent for #{settled_promo.name}")

                {:ok, %{body: body}} ->
                  Logger.error("[HourlyPromoScheduler] Telegram results rejected: #{inspect(body)}")

                {:error, reason} ->
                  Logger.error("[HourlyPromoScheduler] Telegram results request failed: #{inspect(reason)}")
              end
            end
          end
        rescue
          e -> Logger.error("[HourlyPromoScheduler] Telegram Task crashed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}")
        end
      end)

      Logger.info("[HourlyPromoScheduler] Running promo: #{promo.name} (#{promo.category})")

      {:noreply, new_state}
    end
  end

  defp settle_previous_sync(nil), do: nil
  defp settle_previous_sync(promo) do
    try do
      results = PromoEngine.settle_promo(promo)
      Logger.info("[HourlyPromoScheduler] Settled #{promo.name}: #{inspect(results)}")
      %{promo | results: results}
    rescue
      e ->
        Logger.error("[HourlyPromoScheduler] Error settling promo #{promo.name}: #{inspect(e)}")
        nil
    end
  end

  defp schedule_next_promo(old_ref) do
    # Cancel any existing timer to prevent duplicates
    if old_ref, do: Process.cancel_timer(old_ref)

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
        expires_at: promo.expires_at,
        template: serialize_template(promo.template)
      }
      serializable_history = Enum.map(history, fn h ->
        %{id: h.id, name: h.name, category: h.category,
          started_at: h[:started_at], expires_at: h[:expires_at]}
      end) |> Enum.take(24)

      :mnesia.dirty_write({:hourly_promo_state, :current, serializable_promo, DateTime.utc_now(), serializable_history})
    rescue
      _ -> :ok
    end
  end

  defp serialize_template(nil), do: nil
  defp serialize_template(template) do
    Map.drop(template, [:announcement])
  end

  defp restore_state_from_mnesia do
    # Wait for Mnesia to finish loading tables from disk (scheduler starts before MnesiaInitializer completes)
    :mnesia.wait_for_tables([:hourly_promo_state], 10_000)

    case :mnesia.dirty_read(:hourly_promo_state, :current) do
      [{:hourly_promo_state, :current, promo_data, saved_at, history_data}] when is_map(promo_data) ->
        promo = deserialize_promo(promo_data)
        history = (history_data || []) |> Enum.map(&deserialize_promo/1) |> Enum.reject(&is_nil/1)
        Logger.info("[HourlyPromoScheduler] Restored state from Mnesia: #{promo.name}")
        %{current_promo: promo, history: history, promo_started_at: saved_at, forced_category: nil}

      _ ->
        %{current_promo: nil, history: [], promo_started_at: nil, forced_category: nil}
    end
  rescue
    e ->
      Logger.warning("[HourlyPromoScheduler] Mnesia restore rescued: #{inspect(e)}")
      %{current_promo: nil, history: [], promo_started_at: nil, forced_category: nil}
  catch
    :exit, reason ->
      Logger.warning("[HourlyPromoScheduler] Mnesia restore exit: #{inspect(reason)}")
      %{current_promo: nil, history: [], promo_started_at: nil, forced_category: nil}
  end

  defp deserialize_promo(nil), do: nil
  defp deserialize_promo(data) when is_map(data) do
    %{
      id: data[:id],
      name: data[:name],
      category: data[:category],
      started_at: data[:started_at],
      expires_at: data[:expires_at],
      template: data[:template],
      announcement_html: nil,
      results: nil
    }
  end
  defp deserialize_promo(_), do: nil
end
