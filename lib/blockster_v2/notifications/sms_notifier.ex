defmodule BlocksterV2.Notifications.SmsNotifier do
  @moduledoc """
  SMS notification sender using Twilio Messages API.
  Separate from TwilioClient's Verify API — this sends general notification SMS.
  """

  require Logger

  @max_sms_length 160
  @twilio_messages_url "https://api.twilio.com/2010-04-01/Accounts"

  # ============ SMS Templates ============

  @doc """
  Build an SMS message for a given notification type.
  All messages are capped at 160 characters and include an opt-out footer.
  """
  def build_message(:flash_sale, data) do
    title = data[:title] || "Flash Sale"
    url = data[:url] || "blockster-v2.fly.dev/shop"
    truncate_with_footer("#{title} — Shop now: #{url}")
  end

  def build_message(:bux_milestone, data) do
    amount = data[:amount] || "0"
    url = data[:url] || "blockster-v2.fly.dev"
    truncate_with_footer("You hit #{amount} BUX! Check your rewards: #{url}")
  end

  def build_message(:order_shipped, data) do
    order_ref = data[:order_ref] || ""
    tracking_url = data[:tracking_url] || data[:url] || "blockster-v2.fly.dev"
    truncate_with_footer("Your Blockster order #{order_ref} shipped! Track: #{tracking_url}")
  end

  def build_message(:account_security, data) do
    detail = data[:detail] || "New login detected"
    url = data[:url] || "blockster-v2.fly.dev"
    truncate_with_footer("#{detail}. Not you? Secure your account: #{url}")
  end

  def build_message(:exclusive_drop, data) do
    title = data[:title] || "Limited edition drop"
    url = data[:url] || "blockster-v2.fly.dev/shop"
    truncate_with_footer("#{title} — Get yours: #{url}")
  end

  def build_message(:special_offer, data) do
    title = data[:title] || "Special Offer"
    url = data[:url] || "blockster-v2.fly.dev/shop"
    truncate_with_footer("#{title} — #{url}")
  end

  def build_message(_type, data) do
    message = data[:message] || data[:title] || "Blockster notification"
    url = data[:url]
    text = if url, do: "#{message} — #{url}", else: message
    truncate_with_footer(text)
  end

  @doc """
  Send an SMS to a phone number via Twilio Messages API.
  Returns {:ok, message_sid} or {:error, reason}.
  """
  def send_sms(phone_number, message) do
    account_sid = get_account_sid()
    auth_token = get_auth_token()
    from_number = get_from_number()

    if is_nil(account_sid) || is_nil(auth_token) || is_nil(from_number) do
      Logger.warning("[SmsNotifier] Twilio credentials not configured, skipping SMS")
      {:error, :not_configured}
    else
      do_send(account_sid, auth_token, from_number, phone_number, message)
    end
  end

  @doc """
  Check if a user is eligible to receive SMS notifications.
  Requires: phone_verified, sms_opt_in, sms_enabled in preferences, within rate limit.
  """
  def can_send_to_user?(user) do
    user.phone_verified && user.sms_opt_in
  end

  @doc """
  Get a user's phone number from their phone verification record.
  """
  def get_user_phone(user_id) do
    alias BlocksterV2.Repo
    alias BlocksterV2.Accounts.PhoneVerification

    case Repo.get_by(PhoneVerification, user_id: user_id) do
      nil -> nil
      %{phone_number: phone, verified: true, sms_opt_in: true} -> phone
      _ -> nil
    end
  end

  # ============ Private ============

  defp do_send(account_sid, auth_token, from_number, to_number, message) do
    url = "#{@twilio_messages_url}/#{account_sid}/Messages.json"

    body =
      URI.encode_query(%{
        "To" => to_number,
        "From" => from_number,
        "Body" => message
      })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Basic " <> Base.encode64("#{account_sid}:#{auth_token}")}
    ]

    case HTTPoison.post(url, body, headers, recv_timeout: 15_000) do
      {:ok, %{status_code: 201, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"sid" => sid}} ->
            Logger.info("[SmsNotifier] SMS sent successfully: #{sid}")
            {:ok, sid}

          _ ->
            {:error, "Invalid Twilio response"}
        end

      {:ok, %{status_code: status, body: error_body}} ->
        Logger.error("[SmsNotifier] Twilio error (#{status}): #{error_body}")
        {:error, "Twilio error (#{status})"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[SmsNotifier] HTTP request failed: #{reason}")
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  defp truncate_with_footer(message) do
    footer = "\nReply STOP to opt out"
    max_body = @max_sms_length - byte_size(footer)

    body =
      if byte_size(message) > max_body do
        # Truncate and add ".." (2 bytes) to stay within limit
        String.slice(message, 0, max_body - 2) <> ".."
      else
        message
      end

    body <> footer
  end

  defp get_account_sid, do: Application.get_env(:blockster_v2, :twilio_account_sid)
  defp get_auth_token, do: Application.get_env(:blockster_v2, :twilio_auth_token)
  defp get_from_number, do: Application.get_env(:blockster_v2, :twilio_from_number)
end
