defmodule BlocksterV2.Notifications.EventProcessor do
  @moduledoc """
  GenServer that listens to PubSub events and dispatches them to the
  notification engines (TriggerEngine, ConversionFunnelEngine, PriceAlertEngine).

  Runs as a GlobalSingleton — one instance across the cluster.
  """

  use GenServer
  require Logger

  alias BlocksterV2.Notifications.{
    TriggerEngine,
    ConversionFunnelEngine,
    PriceAlertEngine,
    SystemConfig
  }

  @pubsub BlocksterV2.PubSub

  # ============ Client API ============

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  # ============ GenServer Callbacks ============

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, "user_events")
    Phoenix.PubSub.subscribe(@pubsub, "token_prices")

    Logger.info("[EventProcessor] Started — listening on user_events + token_prices")

    {:ok, %{last_rogue_price: nil}}
  end

  @impl true
  def handle_info({:user_event, user_id, event_type, metadata}, state) do
    # Dispatch to engines in a Task to avoid blocking
    Task.start(fn ->
      process_user_event(user_id, event_type, metadata)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:token_prices_updated, prices}, state) do
    new_rogue_price = get_rogue_price(prices)
    old_rogue_price = state.last_rogue_price

    if old_rogue_price && new_rogue_price do
      Task.start(fn ->
        process_price_update(old_rogue_price, new_rogue_price)
      end)
    end

    {:noreply, %{state | last_rogue_price: new_rogue_price}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ============ Event Processing ============

  defp process_user_event(user_id, event_type, metadata) do
    # 1. Evaluate real-time triggers
    try do
      notifications = TriggerEngine.evaluate_triggers(user_id, event_type, metadata)
      if notifications != [] do
        Logger.debug("[EventProcessor] Trigger fired #{length(notifications)} notification(s) for user #{user_id} on #{event_type}")
      end
    rescue
      e -> Logger.warning("[EventProcessor] TriggerEngine error for user #{user_id}: #{inspect(e)}")
    end

    # 2. Evaluate conversion funnel triggers
    try do
      funnel_notifications = ConversionFunnelEngine.evaluate_funnel_triggers(user_id, event_type, metadata)
      if funnel_notifications != [] do
        Logger.debug("[EventProcessor] Funnel fired #{length(funnel_notifications)} notification(s) for user #{user_id} on #{event_type}")
      end
    rescue
      e -> Logger.warning("[EventProcessor] ConversionFunnelEngine error for user #{user_id}: #{inspect(e)}")
    end

    # 3. For key events, enqueue profile recalculation and update conversion stage
    if event_type in ~w(game_played purchase_complete bux_earned article_read_complete) do
      try do
        enqueue_profile_recalc(user_id)
      rescue
        e -> Logger.warning("[EventProcessor] ProfileRecalc enqueue error: #{inspect(e)}")
      end

      try do
        maybe_update_conversion_stage(user_id, event_type, metadata)
      rescue
        e -> Logger.warning("[EventProcessor] Conversion stage update error: #{inspect(e)}")
      end
    end

    # 4. Evaluate custom rules from SystemConfig
    evaluate_custom_rules(user_id, event_type, metadata)
  rescue
    e ->
      Logger.error("[EventProcessor] Unhandled error processing #{event_type} for user #{user_id}: #{inspect(e)}")
  end

  defp process_price_update(old_price, new_price) do
    case PriceAlertEngine.evaluate_price_change(old_price, new_price) do
      {:fire, alert_data} ->
        PriceAlertEngine.fire_price_alerts(alert_data)
        Logger.info("[EventProcessor] Price alert fired: #{alert_data.direction} #{alert_data.change_pct}%")

      :skip ->
        :ok
    end
  rescue
    e -> Logger.warning("[EventProcessor] Price alert error: #{inspect(e)}")
  end

  # ============ Helpers ============

  defp enqueue_profile_recalc(user_id) do
    %{user_id: user_id}
    |> BlocksterV2.Workers.ProfileRecalcWorker.new(
      unique: [period: 300, keys: [:user_id]]
    )
    |> Oban.insert()
  end

  defp maybe_update_conversion_stage(user_id, "game_played", metadata) do
    token = metadata[:token] || metadata["token"]
    profile = BlocksterV2.UserEvents.get_profile(user_id)

    cond do
      # First BUX game → bux_player
      token in ["BUX", "bux"] && profile && profile.conversion_stage in [nil, "earner"] ->
        BlocksterV2.UserEvents.upsert_profile(user_id, %{conversion_stage: "bux_player"})

      # First ROGUE game → rogue_curious
      token in ["ROGUE", "rogue"] && profile && profile.conversion_stage in [nil, "earner", "bux_player"] ->
        BlocksterV2.UserEvents.upsert_profile(user_id, %{conversion_stage: "rogue_curious"})

      true ->
        :ok
    end
  end

  defp maybe_update_conversion_stage(user_id, "purchase_complete", _metadata) do
    profile = BlocksterV2.UserEvents.get_profile(user_id)

    if profile && profile.conversion_stage in [nil, "earner", "bux_player", "rogue_curious"] do
      BlocksterV2.UserEvents.upsert_profile(user_id, %{conversion_stage: "rogue_buyer"})
    end
  end

  defp maybe_update_conversion_stage(_user_id, _event_type, _metadata), do: :ok

  defp evaluate_custom_rules(user_id, event_type, metadata) do
    rules = SystemConfig.get("custom_rules", [])

    Enum.each(rules, fn rule ->
      if matches_rule?(rule, event_type, metadata) do
        execute_rule_action(rule, user_id, event_type, metadata)
      end
    end)
  rescue
    _ -> :ok
  end

  defp matches_rule?(%{"event_type" => rule_event} = rule, event_type, metadata) do
    event_type == rule_event && matches_conditions?(rule["conditions"], metadata)
  end
  defp matches_rule?(_, _, _), do: false

  defp matches_conditions?(nil, _metadata), do: true
  defp matches_conditions?(conditions, metadata) when is_map(conditions) do
    Enum.all?(conditions, fn {key, value} ->
      Map.get(metadata, key) == value || Map.get(metadata, to_string(key)) == value
    end)
  end
  defp matches_conditions?(_, _), do: true

  defp execute_rule_action(%{"action" => "notification", "title" => title, "body" => body} = rule, user_id, _event_type, _metadata) do
    BlocksterV2.Notifications.create_notification(user_id, %{
      type: rule["notification_type"] || "special_offer",
      category: rule["category"] || "engagement",
      title: title,
      body: body,
      action_url: rule["action_url"],
      action_label: rule["action_label"]
    })
  end
  defp execute_rule_action(_, _, _, _), do: :ok

  defp get_rogue_price(prices) when is_map(prices) do
    prices["rogue-chain"] || prices[:rogue_chain] || prices["rogue"]
  end
  defp get_rogue_price(_), do: nil
end
