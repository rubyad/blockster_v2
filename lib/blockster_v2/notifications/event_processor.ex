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
    RateLimiter,
    FormulaEvaluator
  }

  @pubsub BlocksterV2.PubSub

  # Max bonus caps to prevent runaway formulas
  @max_bux_bonus 100_000
  @max_rogue_bonus 100

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

  @doc false
  def process_user_event(user_id, event_type, metadata) do
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
    balances = fetch_user_balances(user_id)

    game_metadata =
      try do
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
      catch
        :exit, _ -> metadata
      end

    Map.merge(game_metadata, balances)
  end

  # Catch-all: enrich all events with BUX/ROGUE balances
  defp enrich_metadata(user_id, _event_type, metadata) do
    Map.merge(metadata, fetch_user_balances(user_id))
  rescue
    _ -> metadata
  end

  defp fetch_user_balances(user_id) do
    balances = BlocksterV2.EngagementTracker.get_user_token_balances(user_id)
    %{
      "bux_balance" => balances["BUX"] || 0.0,
      "rogue_balance" => balances["ROGUE"] || 0.0
    }
  rescue
    _ -> %{"bux_balance" => 0.0, "rogue_balance" => 0.0}
  catch
    :exit, _ -> %{"bux_balance" => 0.0, "rogue_balance" => 0.0}
  end

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
        if rule["recurring"] == true do
          execute_recurring_rule(rule, user_id, event_type, metadata)
        else
          execute_rule_action(rule, user_id, event_type, metadata)
        end
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

  defp execute_rule_action(%{"action" => "notification", "title" => title, "body" => body} = rule, user_id, event_type, enriched_metadata) do
    execute_rule_action_inner(rule, user_id, event_type, enriched_metadata, title, body, nil)
  end
  defp execute_rule_action(_, _, _, _), do: :ok

  # Shared inner logic for both one-shot and recurring rules
  defp execute_rule_action_inner(rule, user_id, event_type, enriched_metadata, title, body, recurring_metadata) do
    dedup_key = build_dedup_key(rule, event_type)

    # For non-recurring rules, check dedup. Recurring rules handle dedup differently (via recurring_metadata).
    if dedup_key && is_nil(recurring_metadata) && Notifications.already_notified?(user_id, dedup_key) do
      :ok
    else
      # Resolve bonus amounts (formula or static)
      bux_bonus = resolve_bonus(rule, "bux", enriched_metadata)
      rogue_bonus = resolve_bonus(rule, "rogue", enriched_metadata)

      channel = rule["channel"] || "in_app"
      notif_metadata = if dedup_key, do: %{"dedup_key" => dedup_key}, else: %{}

      # Include reward amounts in metadata for activity tracking
      notif_metadata =
        notif_metadata
        |> maybe_put_reward("bux_bonus", bux_bonus)
        |> maybe_put_reward("rogue_bonus", rogue_bonus)

      # Merge recurring state metadata if present
      notif_metadata =
        if recurring_metadata, do: Map.merge(notif_metadata, recurring_metadata), else: notif_metadata

      # In-app notification (for "in_app", "both", or "all")
      if channel in ["in_app", "both", "all"] do
        Notifications.create_notification(user_id, %{
          type: rule["notification_type"] || "special_offer",
          category: rule["category"] || "engagement",
          title: title,
          body: body,
          action_url: rule["action_url"],
          action_label: rule["action_label"],
          metadata: notif_metadata
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

      # BUX crediting (formula-resolved)
      if is_number(bux_bonus) and bux_bonus > 0 do
        credit_bux(user_id, bux_bonus)
      end

      # ROGUE crediting (formula-resolved)
      if is_number(rogue_bonus) and rogue_bonus > 0 do
        credit_rogue(user_id, rogue_bonus)
      end

      :ok
    end
  end

  # ============ Formula Bonus Resolution ============

  @doc false
  def resolve_bonus(rule, token_type, metadata) do
    formula_key = "#{token_type}_bonus_formula"
    static_key = "#{token_type}_bonus"
    max_cap = if token_type == "bux", do: @max_bux_bonus, else: @max_rogue_bonus

    result =
      cond do
        # Formula takes precedence
        is_binary(rule[formula_key]) and rule[formula_key] != "" ->
          case FormulaEvaluator.evaluate(rule[formula_key], metadata) do
            {:ok, val} when val > 0 -> min(val, max_cap)
            _ -> nil
          end

        # Fall back to static bonus
        is_number(rule[static_key]) and rule[static_key] > 0 ->
          min(rule[static_key], max_cap)

        true ->
          nil
      end

    # Round to reasonable precision
    case result do
      nil -> nil
      n when is_float(n) -> Float.round(n, 2)
      n -> n
    end
  end

  # ============ Recurring Rules ============

  defp execute_recurring_rule(%{"title" => title, "body" => body} = rule, user_id, event_type, metadata) do
    count_field = rule["count_field"] || "total_bets"
    current_count = get_metadata_value(metadata, count_field)

    if is_nil(current_count) or not is_number(current_count) do
      Logger.debug("[EventProcessor] Recurring rule '#{title}' skipped: count_field '#{count_field}' not found in metadata")
      :ok
    else
      dedup_key = build_recurring_dedup_key(rule, event_type)
      recurring_state = get_recurring_state(user_id, dedup_key)

      case recurring_state do
        nil ->
          # First time: fire immediately, set next trigger
          interval = calculate_interval(rule, metadata)
          next_trigger_at = current_count + interval

          recurring_meta = %{
            "recurring_dedup_key" => dedup_key,
            "next_trigger_at" => next_trigger_at,
            "fired_at_count" => current_count,
            "interval" => interval
          }

          Logger.info("[EventProcessor] Recurring rule '#{title}' fired for user #{user_id} at count #{current_count}, next at #{next_trigger_at}")
          execute_rule_action_inner(rule, user_id, event_type, metadata, title, body, recurring_meta)

        %{"next_trigger_at" => next_trigger_at} when is_number(next_trigger_at) ->
          if current_count >= next_trigger_at do
            # Fire and set new threshold
            interval = calculate_interval(rule, metadata)
            new_next_trigger_at = current_count + interval

            recurring_meta = %{
              "recurring_dedup_key" => dedup_key,
              "next_trigger_at" => new_next_trigger_at,
              "fired_at_count" => current_count,
              "interval" => interval
            }

            Logger.info("[EventProcessor] Recurring rule '#{title}' fired for user #{user_id} at count #{current_count}, next at #{new_next_trigger_at}")
            execute_rule_action_inner(rule, user_id, event_type, metadata, title, body, recurring_meta)
          else
            :ok
          end

        _ ->
          :ok
      end
    end
  end

  defp execute_recurring_rule(_, _, _, _), do: :ok

  defp build_recurring_dedup_key(%{"title" => title}, event_type) when is_binary(title) do
    slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    "recurring_rule:#{event_type}:#{slug}"
  end

  defp build_recurring_dedup_key(_, event_type), do: "recurring_rule:#{event_type}"

  @doc false
  def get_recurring_state(user_id, dedup_key) do
    import Ecto.Query

    from(n in Notifications.Notification,
      where: n.user_id == ^user_id,
      where: fragment("?->>'recurring_dedup_key' = ?", n.metadata, ^dedup_key),
      order_by: [desc: n.inserted_at],
      limit: 1,
      select: n.metadata
    )
    |> Repo.one()
  rescue
    _ -> nil
  end

  @doc false
  def calculate_interval(rule, metadata) do
    cond do
      is_binary(rule["every_n_formula"]) and rule["every_n_formula"] != "" ->
        case FormulaEvaluator.evaluate(rule["every_n_formula"], metadata) do
          {:ok, val} when is_number(val) -> max(1, trunc(val))
          _ -> rule["every_n"] || 10
        end

      is_number(rule["every_n"]) and rule["every_n"] >= 1 ->
        trunc(rule["every_n"])

      true ->
        10
    end
  end

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
  defp has_bonus?(%{"bux_bonus_formula" => f}) when is_binary(f) and f != "", do: true
  defp has_bonus?(%{"rogue_bonus_formula" => f}) when is_binary(f) and f != "", do: true
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
