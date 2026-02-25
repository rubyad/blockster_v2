defmodule BlocksterV2Web.TelegramWebhookController do
  use BlocksterV2Web, :controller
  require Logger

  alias BlocksterV2.{Repo, Accounts, Accounts.User, UserEvents}
  import Ecto.Query

  @doc """
  POST /api/webhooks/telegram
  Receives updates from the Telegram Bot API.
  Handles /start TOKEN deep links for account connection.
  """
  def handle(conn, %{"message" => %{"text" => "/start " <> token, "from" => from}}) do
    token = String.trim(token)
    tg_user_id = to_string(from["id"])
    tg_username = from["username"]
    tg_first_name = from["first_name"] || "there"

    Logger.info("[TelegramWebhook] /start from tg_user=#{tg_user_id} (@#{tg_username}) with token=#{token}")

    case Repo.one(from u in User, where: u.telegram_connect_token == ^token, limit: 1) do
      nil ->
        Logger.warning("[TelegramWebhook] Invalid or expired connect token: #{token}")
        send_telegram_message(tg_user_id, "This link has expired or is invalid. Please generate a new one from your Blockster notification settings.")
        json(conn, %{ok: true})

      %User{telegram_user_id: existing} when not is_nil(existing) ->
        send_telegram_message(tg_user_id, "Your Telegram is already connected to Blockster! You're all set.")
        json(conn, %{ok: true})

      user ->
        # Check if this Telegram account is already linked to another user
        case Repo.one(from u in User, where: u.telegram_user_id == ^tg_user_id, limit: 1) do
          nil ->
            # Link the account
            {:ok, _updated} = Accounts.update_user(user, %{
              telegram_user_id: tg_user_id,
              telegram_username: tg_username,
              telegram_connect_token: nil,
              telegram_connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

            # Track event — custom rules handle BUX rewards
            UserEvents.track(user.id, "telegram_connected", %{
              telegram_user_id: tg_user_id,
              telegram_username: tg_username
            })

            # Check if user is already in the group
            check_group_membership(tg_user_id, user.id)

            send_telegram_message(tg_user_id, "Connected! Welcome #{tg_first_name} — your Telegram is now linked to Blockster.\n\nJoin our group to get notified of new articles and earn BUX: https://t.me/+7bIzOyrYBEc3OTdh")
            json(conn, %{ok: true})

          _existing_user ->
            send_telegram_message(tg_user_id, "This Telegram account is already connected to another Blockster user.")
            json(conn, %{ok: true})
        end
    end
  end

  # Handle chat_member updates (user joined/left the Telegram group)
  def handle(conn, %{"chat_member" => %{
    "chat" => %{"id" => chat_id},
    "new_chat_member" => %{"status" => new_status, "user" => %{"id" => tg_user_id}}
  }}) do
    group_chat_id = Application.get_env(:blockster_v2, :telegram_v2_channel_id)

    if to_string(chat_id) == group_chat_id and new_status in ["member", "administrator", "creator"] do
      track_group_join(to_string(tg_user_id))
    end

    json(conn, %{ok: true})
  end

  # Handle /bot_pause command (admin only)
  def handle(conn, %{"message" => %{"text" => "/bot_pause", "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, :pause)
  end

  # Handle /bot_resume command (admin only)
  def handle(conn, %{"message" => %{"text" => "/bot_resume", "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, :resume)
  end

  # Handle /bot_status command (admin only)
  def handle(conn, %{"message" => %{"text" => "/bot_status", "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, :status)
  end

  # Handle /bot_budget command (admin only)
  def handle(conn, %{"message" => %{"text" => "/bot_budget", "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, :budget)
  end

  # Handle /bot_next [type] command (admin only)
  def handle(conn, %{"message" => %{"text" => "/bot_next " <> type, "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, {:force_next, String.trim(type)})
  end

  def handle(conn, %{"message" => %{"text" => "/bot_next", "from" => %{"id" => tg_user_id}}}) do
    handle_admin_command(conn, tg_user_id, :list_types)
  end

  # Handle messages directed at the bot in the group (promo Q&A)
  def handle(conn, %{"message" => %{"text" => text, "from" => from, "chat" => chat, "message_id" => msg_id} = message})
      when is_binary(text) do
    group_chat_id = Application.get_env(:blockster_v2, :telegram_v2_channel_id)
    chat_id = to_string(chat["id"])

    if chat_id == group_chat_id and from["is_bot"] != true and bot_directed?(text, message) do
      question = text |> String.replace(~r/@\w+/, "") |> String.trim()
      tg_user_id = to_string(from["id"])

      if String.length(question) >= 3 do
        Task.start(fn ->
          case BlocksterV2.TelegramBot.PromoQA.answer_question(question, tg_user_id) do
            {:ok, answer} ->
              send_telegram_reply(chat["id"], answer, msg_id)

            _ ->
              :ok
          end
        end)
      end
    end

    json(conn, %{ok: true})
  end

  def handle(conn, _params) do
    json(conn, %{ok: true})
  end

  # ============ Admin Bot Commands ============

  defp handle_admin_command(conn, tg_user_id, command) do
    tg_id_str = to_string(tg_user_id)

    if is_admin?(tg_id_str) do
      execute_admin_command(tg_id_str, command)
    else
      send_telegram_message(tg_id_str, "You don't have permission to use this command.")
    end

    json(conn, %{ok: true})
  end

  defp is_admin?(telegram_user_id) do
    case Repo.one(
      from u in User,
        where: u.telegram_user_id == ^telegram_user_id,
        where: u.is_admin == true,
        select: u.id
    ) do
      nil -> false
      _id -> true
    end
  end

  defp execute_admin_command(chat_id, :pause) do
    alias BlocksterV2.Notifications.SystemConfig
    SystemConfig.put("hourly_promo_enabled", false, "telegram_admin")
    send_telegram_message(chat_id, "Hourly promo bot PAUSED. Active rules cleaned up.")
  end

  defp execute_admin_command(chat_id, :resume) do
    alias BlocksterV2.Notifications.SystemConfig
    SystemConfig.put("hourly_promo_enabled", true, "telegram_admin")
    send_telegram_message(chat_id, "Hourly promo bot RESUMED. Next promo will run at the top of the hour.")
  end

  defp execute_admin_command(chat_id, :status) do
    alias BlocksterV2.Notifications.SystemConfig
    alias BlocksterV2.TelegramBot.{HourlyPromoScheduler, PromoEngine}

    enabled = SystemConfig.get("hourly_promo_enabled", false)
    budget = PromoEngine.remaining_budget()
    state_info = case HourlyPromoScheduler.get_state() do
      {:ok, info} -> info
      _ -> nil
    end

    current = if state_info && state_info.current_promo,
      do: "#{state_info.current_promo.name} (#{state_info.current_promo.category})",
      else: "None"

    msg = """
    Bot Status: #{if enabled, do: "RUNNING", else: "PAUSED"}
    Current Promo: #{current}
    Budget Remaining: #{budget} / 100,000 BUX
    """
    send_telegram_message(chat_id, String.trim(msg))
  end

  defp execute_admin_command(chat_id, :budget) do
    alias BlocksterV2.TelegramBot.PromoEngine
    state = PromoEngine.get_daily_state()
    msg = """
    Daily BUX Budget:
    Distributed: #{state.total_bux_given} / 100,000 BUX
    Remaining: #{max(100_000 - state.total_bux_given, 0)} BUX
    Users rewarded: #{map_size(state.user_reward_counts)}
    """
    send_telegram_message(chat_id, String.trim(msg))
  end

  defp execute_admin_command(chat_id, {:force_next, type_str}) do
    alias BlocksterV2.TelegramBot.HourlyPromoScheduler
    category = case type_str do
      "game" -> :bux_booster_rule
      "bux_booster" -> :bux_booster_rule
      "referral" -> :referral_boost
      "giveaway" -> :giveaway
      "competition" -> :competition
      _ -> nil
    end

    if category do
      HourlyPromoScheduler.force_next(category)
      send_telegram_message(chat_id, "Next promo forced to: #{category}")
    else
      send_telegram_message(chat_id, "Unknown type: #{type_str}\nValid: game, referral, giveaway, competition")
    end
  end

  defp execute_admin_command(chat_id, :list_types) do
    send_telegram_message(chat_id, "Usage: /bot_next [type]\nTypes: game, referral, giveaway, competition")
  end

  # ============ Private Helpers ============

  defp bot_directed?(text, message) do
    # Check if message @mentions the bot
    String.contains?(String.downcase(text), "@blocksterv2bot") or
      # Check if it's a reply to a bot message
      get_in(message, ["reply_to_message", "from", "is_bot"]) == true
  end

  defp send_telegram_reply(chat_id, text, reply_to_message_id) do
    token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
    if token do
      Req.post("https://api.telegram.org/bot#{token}/sendMessage",
        json: %{chat_id: chat_id, text: text, reply_to_message_id: reply_to_message_id},
        receive_timeout: 10_000
      )
    end
  end

  defp send_telegram_message(chat_id, text) do
    token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
    if token do
      Task.start(fn ->
        Req.post("https://api.telegram.org/bot#{token}/sendMessage",
          json: %{chat_id: chat_id, text: text},
          receive_timeout: 10_000
        )
      end)
    end
  end

  defp track_group_join(tg_user_id) do
    case Repo.one(from u in User, where: u.telegram_user_id == ^tg_user_id, limit: 1) do
      nil ->
        Logger.debug("[TelegramWebhook] No user linked to tg_user_id=#{tg_user_id}, skipping group join tracking")

      %User{telegram_group_joined_at: joined_at} when not is_nil(joined_at) ->
        Logger.debug("[TelegramWebhook] User with tg_user_id=#{tg_user_id} already tracked as group member")

      user ->
        {:ok, _} = Accounts.update_user(user, %{
          telegram_group_joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        UserEvents.track(user.id, "telegram_group_joined", %{
          source: "webhook",
          telegram_user_id: tg_user_id
        })

        Logger.info("[TelegramWebhook] Tracked group join for user #{user.id} (tg_user_id=#{tg_user_id})")
    end
  rescue
    e -> Logger.warning("[TelegramWebhook] Error tracking group join: #{inspect(e)}")
  end

  defp check_group_membership(tg_user_id, user_id) do
    group_chat_id = Application.get_env(:blockster_v2, :telegram_v2_channel_id)
    token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)

    if group_chat_id && token do
      Task.start(fn ->
        try do
          case Req.get("https://api.telegram.org/bot#{token}/getChatMember",
                 params: [chat_id: group_chat_id, user_id: tg_user_id],
                 receive_timeout: 10_000
               ) do
            {:ok, %{status: 200, body: %{"ok" => true, "result" => %{"status" => status}}}}
            when status in ["member", "administrator", "creator"] ->
              track_group_join(to_string(tg_user_id))

            {:ok, %{body: body}} ->
              Logger.debug("[TelegramWebhook] User #{user_id} not in group: #{inspect(body)}")

            {:error, reason} ->
              Logger.warning("[TelegramWebhook] Failed to check group membership for user #{user_id}: #{inspect(reason)}")
          end
        rescue
          e -> Logger.warning("[TelegramWebhook] Error checking group membership: #{inspect(e)}")
        end
      end)
    end
  end
end
