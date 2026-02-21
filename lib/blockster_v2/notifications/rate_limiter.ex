defmodule BlocksterV2.Notifications.RateLimiter do
  @moduledoc """
  Rate limiter for notification delivery.
  Checks user preferences, daily/weekly limits, quiet hours, and per-type opt-outs.
  """

  alias BlocksterV2.Notifications

  @doc """
  Checks if a notification can be sent to a user via the given channel.

  Returns:
  - :ok — safe to send
  - :defer — in quiet hours, should reschedule
  - {:error, reason} — should not send
  """
  def can_send?(user_id, channel, type \\ nil) do
    case Notifications.get_preferences(user_id) do
      nil ->
        {:error, :no_preferences}

      prefs ->
        check_chain(prefs, user_id, channel, type)
    end
  end

  defp check_chain(prefs, user_id, channel, type) do
    with :ok <- check_channel_enabled(prefs, channel),
         :ok <- check_type_enabled(prefs, channel, type),
         :ok <- check_rate_limit(prefs, user_id, channel),
         :ok <- check_quiet_hours(prefs) do
      :ok
    end
  end

  # ============ Channel Enabled ============

  defp check_channel_enabled(prefs, :email) do
    if prefs.email_enabled, do: :ok, else: {:error, :channel_disabled}
  end

  defp check_channel_enabled(prefs, :sms) do
    if prefs.sms_enabled, do: :ok, else: {:error, :channel_disabled}
  end

  defp check_channel_enabled(prefs, :in_app) do
    if prefs.in_app_enabled, do: :ok, else: {:error, :channel_disabled}
  end

  defp check_channel_enabled(_prefs, _), do: :ok

  # ============ Per-Type Opt-Out ============

  defp check_type_enabled(_prefs, _channel, nil), do: :ok

  defp check_type_enabled(prefs, :email, type) do
    field = email_pref_field(type)

    if field do
      if Map.get(prefs, field, true), do: :ok, else: {:error, :type_disabled}
    else
      :ok
    end
  end

  defp check_type_enabled(prefs, :sms, type) do
    field = sms_pref_field(type)

    if field do
      if Map.get(prefs, field, true), do: :ok, else: {:error, :type_disabled}
    else
      :ok
    end
  end

  defp check_type_enabled(_prefs, _channel, _type), do: :ok

  # ============ Rate Limits ============

  defp check_rate_limit(prefs, user_id, :email) do
    sent_today = Notifications.emails_sent_today(user_id)

    if sent_today >= prefs.max_emails_per_day do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  defp check_rate_limit(prefs, user_id, :sms) do
    sent_this_week = Notifications.sms_sent_this_week(user_id)

    if sent_this_week >= prefs.max_sms_per_week do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  defp check_rate_limit(_prefs, _user_id, _channel), do: :ok

  # ============ Quiet Hours ============

  defp check_quiet_hours(%{quiet_hours_start: nil}), do: :ok
  defp check_quiet_hours(%{quiet_hours_end: nil}), do: :ok

  defp check_quiet_hours(prefs) do
    now_utc = DateTime.utc_now() |> DateTime.to_time() |> Time.truncate(:second)

    # Convert current time to user's timezone
    user_time = shift_to_timezone(now_utc, prefs.timezone)

    if in_quiet_hours?(user_time, prefs.quiet_hours_start, prefs.quiet_hours_end) do
      :defer
    else
      :ok
    end
  end

  defp in_quiet_hours?(current, start_time, end_time) do
    if Time.compare(start_time, end_time) == :gt do
      # Spans midnight (e.g., 22:00 -> 08:00)
      Time.compare(current, start_time) != :lt or Time.compare(current, end_time) == :lt
    else
      # Same day (e.g., 01:00 -> 06:00)
      Time.compare(current, start_time) != :lt and Time.compare(current, end_time) == :lt
    end
  end

  # Simple timezone offset — enough for rate limiting purposes
  defp shift_to_timezone(time, "UTC"), do: time
  defp shift_to_timezone(time, tz) do
    offset_hours = timezone_offset(tz)
    seconds = Time.to_seconds_after_midnight(time) + offset_hours * 3600
    # Wrap around midnight
    seconds = rem(seconds + 86400, 86400)
    Time.from_seconds_after_midnight(seconds)
  end

  defp timezone_offset("US/Eastern"), do: -5
  defp timezone_offset("US/Central"), do: -6
  defp timezone_offset("US/Mountain"), do: -7
  defp timezone_offset("US/Pacific"), do: -8
  defp timezone_offset("US/Alaska"), do: -9
  defp timezone_offset("US/Hawaii"), do: -10
  defp timezone_offset("Europe/London"), do: 0
  defp timezone_offset("Europe/Paris"), do: 1
  defp timezone_offset("Europe/Berlin"), do: 1
  defp timezone_offset("Europe/Moscow"), do: 3
  defp timezone_offset("Asia/Dubai"), do: 4
  defp timezone_offset("Asia/Kolkata"), do: 5
  defp timezone_offset("Asia/Singapore"), do: 8
  defp timezone_offset("Asia/Shanghai"), do: 8
  defp timezone_offset("Asia/Tokyo"), do: 9
  defp timezone_offset("Australia/Sydney"), do: 11
  defp timezone_offset("Pacific/Auckland"), do: 13
  defp timezone_offset(_), do: 0

  # ============ Preference Field Mapping ============

  defp email_pref_field("hub_post"), do: :email_hub_posts
  defp email_pref_field("new_article"), do: :email_new_articles
  defp email_pref_field("special_offer"), do: :email_special_offers
  defp email_pref_field("flash_sale"), do: :email_special_offers
  defp email_pref_field("daily_digest"), do: :email_daily_digest
  defp email_pref_field("weekly_roundup"), do: :email_weekly_roundup
  defp email_pref_field("referral_prompt"), do: :email_referral_prompts
  defp email_pref_field("bux_earned"), do: :email_reward_alerts
  defp email_pref_field("bux_milestone"), do: :email_reward_alerts
  defp email_pref_field("reward_summary"), do: :email_reward_alerts
  defp email_pref_field("shop_new_product"), do: :email_shop_deals
  defp email_pref_field("shop_restock"), do: :email_shop_deals
  defp email_pref_field("price_drop"), do: :email_shop_deals
  defp email_pref_field("cart_abandonment"), do: :email_shop_deals
  defp email_pref_field("account_security"), do: :email_account_updates
  defp email_pref_field("welcome"), do: :email_account_updates
  defp email_pref_field("re_engagement"), do: :email_re_engagement
  defp email_pref_field(_), do: nil

  defp sms_pref_field("special_offer"), do: :sms_special_offers
  defp sms_pref_field("flash_sale"), do: :sms_special_offers
  defp sms_pref_field("account_security"), do: :sms_account_alerts
  defp sms_pref_field("order_shipped"), do: :sms_account_alerts
  defp sms_pref_field("bux_milestone"), do: :sms_milestone_rewards
  defp sms_pref_field(_), do: nil
end
