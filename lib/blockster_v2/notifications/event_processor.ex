defmodule BlocksterV2.Notifications.EventProcessor do
  @moduledoc """
  GenServer that listens to PubSub events and dispatches them to the
  notification engines (TriggerEngine, custom rules).

  Runs as a GlobalSingleton — one instance across the cluster.
  """

  use GenServer
  require Logger

  alias BlocksterV2.{Repo, Mailer, Notifications}
  alias BlocksterV2.Notifications.{
    TriggerEngine,
    SystemConfig,
    EmailBuilder,
    RateLimiter
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

    Logger.info("[EventProcessor] Started — listening on user_events")

    {:ok, %{}}
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

    # 2. Enrich metadata for game events, then evaluate custom rules
    enriched_metadata = enrich_metadata(user_id, event_type, metadata)
    evaluate_custom_rules(user_id, event_type, enriched_metadata)
  rescue
    e ->
      Logger.error("[EventProcessor] Unhandled error processing #{event_type} for user #{user_id}: #{inspect(e)}")
  end

  # ============ Helpers ============

  defp enrich_metadata(user_id, "game_played", metadata) do
    case BlocksterV2.BuxBoosterStats.get_user_stats(user_id) do
      {:ok, stats} ->
        Map.merge(metadata, %{
          # Counts
          "total_bets" => (stats.bux.total_bets || 0) + (stats.rogue.total_bets || 0),
          "bux_total_bets" => stats.bux.total_bets || 0,
          "rogue_total_bets" => stats.rogue.total_bets || 0,
          "bux_wins" => stats.bux.wins || 0,
          "bux_losses" => stats.bux.losses || 0,
          "rogue_wins" => stats.rogue.wins || 0,
          "rogue_losses" => stats.rogue.losses || 0,
          # Amounts (converted from wei to human-readable)
          "bux_total_wagered" => wei_to_float(stats.bux.total_wagered),
          "bux_total_winnings" => wei_to_float(stats.bux.total_winnings),
          "bux_total_losses" => wei_to_float(stats.bux.total_losses),
          "bux_net_pnl" => wei_to_float(stats.bux.net_pnl),
          "rogue_total_wagered" => wei_to_float(stats.rogue.total_wagered),
          "rogue_total_winnings" => wei_to_float(stats.rogue.total_winnings),
          "rogue_total_losses" => wei_to_float(stats.rogue.total_losses),
          "rogue_net_pnl" => wei_to_float(stats.rogue.net_pnl),
          # Win rates
          "bux_win_rate" => win_rate(stats.bux.wins, stats.bux.total_bets),
          "rogue_win_rate" => win_rate(stats.rogue.wins, stats.rogue.total_bets),
          # Timestamps
          "first_bet_at" => stats.first_bet_at,
          "last_bet_at" => stats.last_bet_at
        })

      _ ->
        metadata
    end
  rescue
    _ -> metadata
  end

  defp enrich_metadata(_user_id, _event_type, metadata), do: metadata

  defp wei_to_float(nil), do: 0.0
  defp wei_to_float(wei) when is_integer(wei), do: Float.round(wei / 1_000_000_000_000_000_000, 2)
  defp wei_to_float(_), do: 0.0

  defp win_rate(_, 0), do: 0.0
  defp win_rate(nil, _), do: 0.0
  defp win_rate(wins, total), do: Float.round(wins / total * 100, 1)

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
    Enum.all?(conditions, fn {key, expected} ->
      actual = get_metadata_value(metadata, key)
      match_value?(actual, expected)
    end)
  end
  defp matches_conditions?(_, _), do: true

  defp match_value?(actual, %{"$gte" => threshold}) when is_number(actual), do: actual >= threshold
  defp match_value?(actual, %{"$lte" => threshold}) when is_number(actual), do: actual <= threshold
  defp match_value?(actual, %{"$gt" => threshold}) when is_number(actual), do: actual > threshold
  defp match_value?(actual, %{"$lt" => threshold}) when is_number(actual), do: actual < threshold
  defp match_value?(_actual, expected) when is_map(expected), do: false
  defp match_value?(actual, expected), do: actual == expected

  defp execute_rule_action(%{"action" => "notification", "title" => title, "body" => body} = rule, user_id, event_type, _metadata) do
    dedup_key = build_dedup_key(rule, event_type)

    # If there's a dedup key, check if already notified
    if dedup_key && Notifications.already_notified?(user_id, dedup_key) do
      :ok
    else
      channel = rule["channel"] || "in_app"
      metadata = if dedup_key, do: %{"dedup_key" => dedup_key}, else: %{}

      # Include reward amounts in metadata for activity tracking
      metadata =
        metadata
        |> maybe_put_reward("bux_bonus", rule["bux_bonus"])
        |> maybe_put_reward("rogue_bonus", rule["rogue_bonus"])

      # In-app notification (for "in_app", "both", or "all")
      if channel in ["in_app", "both", "all"] do
        Notifications.create_notification(user_id, %{
          type: rule["notification_type"] || "special_offer",
          category: rule["category"] || "engagement",
          title: title,
          body: body,
          action_url: rule["action_url"],
          action_label: rule["action_label"],
          metadata: metadata
        })
      end

      # Email (for "email" or "both" or "all")
      if channel in ["email", "both", "all"] do
        send_rule_email(user_id, rule, dedup_key)
      end

      # Telegram DM (for "telegram" or "all")
      if channel in ["telegram", "all"] do
        send_rule_telegram(user_id, rule)
      end

      # BUX crediting
      if (bux_bonus = rule["bux_bonus"]) && is_number(bux_bonus) && bux_bonus > 0 do
        credit_bux(user_id, bux_bonus)
      end

      # ROGUE crediting
      if (rogue_bonus = rule["rogue_bonus"]) && is_number(rogue_bonus) && rogue_bonus > 0 do
        credit_rogue(user_id, rogue_bonus)
      end
    end
  end
  defp execute_rule_action(_, _, _, _), do: :ok

  defp send_rule_email(user_id, rule, dedup_key \\ nil) do
    import Ecto.Query

    user = Repo.one(from u in BlocksterV2.Accounts.User, where: u.id == ^user_id, select: %{email: u.email, username: u.username})

    if user && user.email do
      notification_type = rule["notification_type"] || "special_offer"

      case RateLimiter.can_send?(user_id, :email, notification_type) do
        :ok ->
          prefs = Notifications.get_preferences(user_id)
          unsubscribe_token = if prefs, do: prefs.unsubscribe_token, else: nil

          email = EmailBuilder.promotional(
            user.email,
            user.username || "Blockster User",
            unsubscribe_token,
            %{
              title: rule["title"],
              body: rule["body"],
              action_url: rule["action_url"],
              action_label: rule["action_label"]
            }
          )
          |> Swoosh.Email.subject(rule["subject"] || rule["title"])

          case Mailer.deliver(email) do
            {:ok, _} ->
              log_metadata = if dedup_key, do: %{"dedup_key" => dedup_key}, else: %{}
              Notifications.create_email_log(%{
                user_id: user_id,
                email_type: "custom_rule",
                subject: rule["subject"] || rule["title"],
                sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
                metadata: log_metadata
              })
              Logger.info("[EventProcessor] Sent custom rule email to user #{user_id}")

            {:error, reason} ->
              Logger.warning("[EventProcessor] Failed to send rule email to user #{user_id}: #{inspect(reason)}")
          end

        _ ->
          Logger.debug("[EventProcessor] Rate limited email for user #{user_id}")
      end
    end
  rescue
    e -> Logger.warning("[EventProcessor] Error sending rule email for user #{user_id}: #{inspect(e)}")
  end

  defp send_rule_telegram(user_id, rule) do
    import Ecto.Query

    user = Repo.one(from u in BlocksterV2.Accounts.User, where: u.id == ^user_id, select: %{telegram_user_id: u.telegram_user_id})

    if user && user.telegram_user_id do
      token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)

      if token do
        message = rule["body"] || rule["title"] || ""

        Task.start(fn ->
          case Req.post("https://api.telegram.org/bot#{token}/sendMessage",
                 json: %{chat_id: user.telegram_user_id, text: message},
                 receive_timeout: 10_000
               ) do
            {:ok, %{status: 200}} ->
              Logger.info("[EventProcessor] Sent Telegram DM to user #{user_id}")

            {:ok, %{status: status} = resp} ->
              Logger.warning("[EventProcessor] Telegram DM failed for user #{user_id}: #{status} - #{inspect(resp.body)}")

            {:error, reason} ->
              Logger.warning("[EventProcessor] Telegram DM error for user #{user_id}: #{inspect(reason)}")
          end
        end)
      end
    else
      Logger.debug("[EventProcessor] User #{user_id} has no Telegram connected, skipping DM")
    end
  rescue
    e -> Logger.warning("[EventProcessor] Error sending Telegram DM for user #{user_id}: #{inspect(e)}")
  end

  defp credit_bux(user_id, amount) do
    import Ecto.Query

    user = Repo.one(from u in BlocksterV2.Accounts.User, where: u.id == ^user_id, select: %{smart_wallet_address: u.smart_wallet_address})

    if user && user.smart_wallet_address do
      wallet = user.smart_wallet_address

      Task.start(fn ->
        case BlocksterV2.BuxMinter.mint_bux(wallet, amount, user_id, nil, :ai_bonus) do
          {:ok, _} ->
            BlocksterV2.BuxMinter.sync_user_balances_async(user_id, wallet, force: true)
            Logger.info("[EventProcessor] Credited #{amount} BUX to user #{user_id}")

          {:error, reason} ->
            Logger.warning("[EventProcessor] Failed to credit BUX to user #{user_id}: #{inspect(reason)}")
        end
      end)
    else
      Logger.debug("[EventProcessor] User #{user_id} has no smart wallet, skipping BUX credit")
    end
  rescue
    e -> Logger.warning("[EventProcessor] Error crediting BUX for user #{user_id}: #{inspect(e)}")
  end

  defp credit_rogue(user_id, amount) do
    import Ecto.Query

    user = Repo.one(from u in BlocksterV2.Accounts.User, where: u.id == ^user_id, select: %{smart_wallet_address: u.smart_wallet_address})

    if user && user.smart_wallet_address do
      wallet = user.smart_wallet_address

      Task.start(fn ->
        case BlocksterV2.BuxMinter.transfer_rogue(wallet, amount, user_id, "custom_rule") do
          {:ok, _} ->
            BlocksterV2.BuxMinter.sync_user_balances_async(user_id, wallet, force: true)
            Logger.info("[EventProcessor] Credited #{amount} ROGUE to user #{user_id}")

          {:error, reason} ->
            Logger.warning("[EventProcessor] Failed to credit ROGUE to user #{user_id}: #{inspect(reason)}")
        end
      end)
    else
      Logger.debug("[EventProcessor] User #{user_id} has no smart wallet, skipping ROGUE credit")
    end
  rescue
    e -> Logger.warning("[EventProcessor] Error crediting ROGUE for user #{user_id}: #{inspect(e)}")
  end

  defp build_dedup_key(%{"conditions" => conditions, "event_type" => event_type}, _fallback_event)
       when is_map(conditions) and map_size(conditions) > 0 do
    parts =
      conditions
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn
        {key, %{"$gte" => v}} -> "#{key}_gte_#{v}"
        {key, %{"$lte" => v}} -> "#{key}_lte_#{v}"
        {key, %{"$gt" => v}} -> "#{key}_gt_#{v}"
        {key, %{"$lt" => v}} -> "#{key}_lt_#{v}"
        {key, v} -> "#{key}_eq_#{v}"
      end)
      |> Enum.join(":")

    "custom_rule:#{event_type}:#{parts}"
  end

  # One-time reward events — always dedup even without conditions
  @one_time_events ~w(telegram_connected telegram_group_joined phone_verified x_connected wallet_connected)
  defp build_dedup_key(_rule, event_type) when event_type in @one_time_events do
    "custom_rule:#{event_type}"
  end

  # Rules with bonuses should always dedup to prevent repeat payouts
  defp build_dedup_key(%{"title" => title} = rule, event_type) when is_binary(title) do
    if has_bonus?(rule) do
      slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
      "custom_rule:#{event_type}:#{slug}"
    else
      nil
    end
  end

  defp build_dedup_key(_rule, _event_type), do: nil

  defp has_bonus?(%{"bux_bonus" => b}) when is_number(b) and b > 0, do: true
  defp has_bonus?(%{"rogue_bonus" => r}) when is_number(r) and r > 0, do: true
  defp has_bonus?(_), do: false

  # Look up a metadata value by string key, falling back to atom key
  defp get_metadata_value(metadata, key) when is_binary(key) do
    case Map.get(metadata, key) do
      nil ->
        try do
          Map.get(metadata, String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end
      val -> val
    end
  end

  defp maybe_put_reward(metadata, _key, nil), do: metadata
  defp maybe_put_reward(metadata, _key, v) when not is_number(v) or v <= 0, do: metadata
  defp maybe_put_reward(metadata, key, v), do: Map.put(metadata, key, v)
end
