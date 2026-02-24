defmodule BlocksterV2.TelegramBot.TelegramGroupMessenger do
  @moduledoc """
  Sends rich formatted messages to the Blockster Telegram group.
  Uses the V2 bot token and group chat ID from config.
  """
  require Logger

  @telegram_api "https://api.telegram.org"

  @doc "Send a promo announcement to the group and pin it"
  def announce_promo(promo) do
    case send_group_message(promo.announcement_html) do
      {:ok, %{body: %{"ok" => true, "result" => %{"message_id" => msg_id}}}} = result ->
        unpin_all_and_pin(msg_id)
        result

      other ->
        other
    end
  end

  @doc "Send promo results to the group"
  def announce_results(results_html) do
    send_group_message(results_html)
  end

  @doc "Send a text update (leaderboard, urgency reminder, etc.)"
  def send_update(html_text) do
    send_group_message(html_text)
  end

  @doc "Send an HTML message to the configured Telegram group"
  def send_group_message(html_text, opts \\ []) do
    token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
    chat_id = Application.get_env(:blockster_v2, :telegram_v2_channel_id)

    if token && chat_id do
      Req.post("#{@telegram_api}/bot#{token}/sendMessage",
        json: %{
          chat_id: chat_id,
          text: html_text,
          parse_mode: "HTML",
          disable_web_page_preview: Keyword.get(opts, :disable_preview, true)
        },
        receive_timeout: 30_000
      )
    else
      Logger.warning("[TelegramGroupMessenger] Missing bot token or channel ID")
      {:error, :missing_config}
    end
  end

  @doc "Unpin all bot messages then pin a new one (silently)"
  defp unpin_all_and_pin(message_id) do
    token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
    chat_id = Application.get_env(:blockster_v2, :telegram_v2_channel_id)

    if token && chat_id do
      # Unpin all messages first (removes previous promo pin)
      Req.post("#{@telegram_api}/bot#{token}/unpinAllChatMessages",
        json: %{chat_id: chat_id},
        receive_timeout: 10_000
      )

      # Pin the new promo announcement silently
      Req.post("#{@telegram_api}/bot#{token}/pinChatMessage",
        json: %{chat_id: chat_id, message_id: message_id, disable_notification: true},
        receive_timeout: 10_000
      )
    end
  rescue
    e -> Logger.warning("[TelegramGroupMessenger] Pin/unpin failed: #{inspect(e)}")
  end
end
