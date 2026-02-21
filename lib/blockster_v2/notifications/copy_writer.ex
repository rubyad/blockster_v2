defmodule BlocksterV2.Notifications.CopyWriter do
  @moduledoc """
  Generates personalized subject lines and body copy for emails
  based on user engagement tier and behavior.
  """

  @doc "Generate personalized daily digest subject line."
  def digest_subject(nil), do: "Your daily Blockster briefing"
  def digest_subject(profile) do
    case profile.engagement_tier do
      "new" -> "Your daily Blockster briefing is ready"
      "casual" -> "#{profile.articles_read_last_7d} articles picked for you today"
      "active" -> "Today's top stories from your hubs"
      "power" -> "#{hub_count(profile)} hubs have new content for you"
      "whale" -> "Exclusive: your personalized daily brief"
      "dormant" -> "We've been saving stories for you"
      "churned" -> "Here's what you've been missing"
      _ -> "Don't miss today's top stories"
    end
  end

  @doc "Generate personalized referral prompt subject line."
  def referral_subject(nil), do: "Invite friends to Blockster, earn 500 BUX each"
  def referral_subject(profile) do
    cond do
      profile.referrals_converted > 0 ->
        "Your referrals are working — keep going!"

      Decimal.compare(profile.bux_earned_last_30d || Decimal.new("0"), Decimal.new("1000")) == :gt ->
        "You earned BUX this month — share the love"

      profile.purchase_count > 0 ->
        "Give your friends a head start, get 500 BUX for yourself"

      true ->
        "Invite friends to Blockster, earn 500 BUX each"
    end
  end

  @doc "Generate cart abandonment subject line based on time since abandon."
  def cart_abandonment_subject(hours_since_abandon) do
    cond do
      hours_since_abandon < 4 -> "You left something in your cart"
      hours_since_abandon < 24 -> "Your cart is waiting — complete your order"
      hours_since_abandon < 48 -> "Last chance: your cart items are going fast"
      true -> "We saved your cart — here's a little something to help you decide"
    end
  end

  @doc "Generate re-engagement subject line based on days inactive."
  def re_engagement_subject(nil, days_inactive), do: re_engagement_subject_default(days_inactive)
  def re_engagement_subject(profile, days_inactive) do
    case profile.engagement_tier do
      "dormant" -> re_engagement_subject_default(days_inactive)
      "churned" -> "Special welcome back offer — just for you"
      _ -> re_engagement_subject_default(days_inactive)
    end
  end

  @doc "Generate welcome series subject for a specific day."
  def welcome_subject(day) do
    case day do
      0 -> "Welcome to Blockster!"
      3 -> "You're earning BUX by reading"
      5 -> "Discover your hubs"
      7 -> "Invite friends, earn together"
      _ -> "Here's what's new on Blockster"
    end
  end

  @doc "Generate weekly reward summary subject."
  def reward_summary_subject(nil), do: "Your weekly BUX report"
  def reward_summary_subject(profile) do
    earned = profile.bux_earned_last_30d || Decimal.new("0")

    cond do
      Decimal.compare(earned, Decimal.new("500")) == :gt ->
        "Great week! Your BUX report is ready"

      Decimal.compare(earned, Decimal.new("0")) == :gt ->
        "Your weekly BUX report"

      true ->
        "Your BUX balance is waiting — start earning"
    end
  end

  @doc "Generate CTA text based on notification type and tier."
  def cta_text(type, tier \\ "active")
  def cta_text("daily_digest", "new"), do: "Start reading"
  def cta_text("daily_digest", _), do: "Read today's articles"
  def cta_text("referral_prompt", _), do: "Share with friends"
  def cta_text("cart_abandonment", _), do: "Complete your order"
  def cta_text("re_engagement", "churned"), do: "Come back to Blockster"
  def cta_text("re_engagement", _), do: "See what you missed"
  def cta_text("welcome", _), do: "Get started"
  def cta_text("reward_summary", _), do: "View your stats"
  def cta_text(_, _), do: "Learn more"

  # ============ Private ============

  defp hub_count(profile) do
    length(profile.preferred_hubs || [])
  end

  defp re_engagement_subject_default(days_inactive) do
    cond do
      days_inactive <= 3 -> "You have unread articles from your hubs"
      days_inactive <= 7 -> "Your BUX are waiting — claim your rewards"
      days_inactive <= 14 -> "We miss you! Here's what's new"
      true -> "Special welcome back offer — just for you"
    end
  end
end
