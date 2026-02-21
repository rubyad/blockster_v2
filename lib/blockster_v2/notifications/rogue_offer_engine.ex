defmodule BlocksterV2.Notifications.RogueOfferEngine do
  @moduledoc """
  Scores users for ROGUE readiness and identifies conversion candidates.
  Drives users through the BUX→ROGUE conversion funnel.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.{UserProfile, Notification}

  @doc """
  Calculate a ROGUE readiness score (0.0-1.0) for a user profile.
  Higher scores indicate users more likely to convert from BUX to ROGUE.

  Scoring dimensions:
  - BUX game frequency (0.25)
  - BUX wager size (0.20)
  - Engagement factor (0.15)
  - Purchase history (0.10)
  - Referral factor (0.10)
  - Content interest (0.15)
  - Tenure factor (0.05)
  """
  def calculate_rogue_readiness(nil), do: 0.0
  def calculate_rogue_readiness(%UserProfile{} = profile) do
    bux_game_freq = min((profile.games_played_last_30d || 0) / 30, 1.0) * 0.25

    avg_bet = decimal_to_float(profile.avg_bet_size)
    bux_wager_size = min(avg_bet / 1000, 1.0) * 0.20

    engagement = engagement_tier_score(profile.engagement_tier) * 0.15

    purchase_hist = min((profile.purchase_count || 0) / 3, 1.0) * 0.10

    referral = min((profile.referrals_converted || 0) / 2, 1.0) * 0.10

    content = min((profile.articles_read_last_30d || 0) / 20, 1.0) * 0.15

    tenure = min((profile.lifetime_days || 0) / 30, 1.0) * 0.05

    score = bux_game_freq + bux_wager_size + engagement + purchase_hist + referral + content + tenure
    Float.round(min(max(score, 0.0), 1.0), 3)
  end

  @doc """
  Get top N users for ROGUE conversion offers.
  Filters to users in BUX-playing tiers who haven't received a ROGUE offer recently.
  Returns [{profile, score}] sorted by score descending.
  """
  def get_rogue_offer_candidates(count \\ 50) do
    eligible_tiers = ["casual_gambler", "regular_gambler"]
    eligible_stages = ["earner", "bux_player"]
    fourteen_days_ago = DateTime.utc_now() |> DateTime.add(-14, :day) |> DateTime.truncate(:second)

    profiles =
      from(p in UserProfile,
        where: p.gambling_tier in ^eligible_tiers or p.conversion_stage in ^eligible_stages,
        where: p.total_bets_placed > 0,
        where: is_nil(p.last_rogue_offer_at) or p.last_rogue_offer_at < ^fourteen_days_ago
      )
      |> Repo.all()

    profiles
    |> Enum.map(fn profile ->
      score = calculate_rogue_readiness(profile)
      {profile, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(count)
  end

  @doc """
  Classify VIP tier based on ROGUE gambling activity.
  Returns one of: "none", "bronze", "silver", "gold", "diamond"
  """
  def classify_vip_tier(profile) do
    rogue_games = profile.total_rogue_games || 0
    total_rogue_wagered = decimal_to_float(profile.total_rogue_wagered)

    cond do
      total_rogue_wagered > 100 and rogue_games > 100 ->
        "diamond"

      rogue_games >= 100 ->
        "gold"

      rogue_games >= 50 ->
        "silver"

      rogue_games >= 10 ->
        "bronze"

      true ->
        "none"
    end
  end

  @doc """
  Classify the conversion funnel stage for a user.
  Returns one of: "earner", "bux_player", "rogue_curious", "rogue_buyer", "rogue_regular"
  """
  def classify_conversion_stage(profile) do
    rogue_games = profile.total_rogue_games || 0
    bux_games = profile.total_bets_placed || 0
    total_wagered = decimal_to_float(profile.total_wagered)

    cond do
      rogue_games > 5 ->
        "rogue_regular"

      rogue_games > 0 ->
        "rogue_buyer"

      bux_games > 5 and total_wagered > 5000 ->
        "rogue_curious"

      bux_games > 0 ->
        "bux_player"

      true ->
        "earner"
    end
  end

  @doc """
  Calculate the appropriate ROGUE airdrop amount based on readiness score.
  Returns amount in ROGUE tokens.
  """
  def calculate_airdrop_amount(_profile, score) do
    cond do
      score > 0.8 -> 2.0
      score > 0.6 -> 1.0
      score > 0.4 -> 0.5
      true -> 0.25
    end
  end

  @doc """
  Generate a contextual reason message for the ROGUE airdrop.
  """
  def airdrop_reason(profile) do
    cond do
      (profile.total_bets_placed || 0) > 20 ->
        "You're a BUX Booster regular — time to try ROGUE!"

      (profile.engagement_score || 0) > 80 ->
        "You're one of our most active members — VIP ROGUE bonus"

      (profile.purchase_count || 0) > 0 ->
        "As a Blockster shopper, here's something extra"

      true ->
        "We think you'll love ROGUE gaming"
    end
  end

  @doc """
  Check if a user has received a ROGUE offer within the given number of days.
  """
  def received_rogue_offer_recently?(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 14)
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)
    since_naive = DateTime.to_naive(since)

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type in ["special_offer", "flash_sale"],
      where: fragment("?->>'offer_type' = 'rogue_airdrop'", n.metadata),
      where: n.inserted_at >= ^since_naive
    )
    |> Repo.exists?()
  end

  @doc """
  Mark that a ROGUE offer was sent to a user (updates profile timestamp).
  """
  def mark_rogue_offer_sent(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(p in UserProfile, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [last_rogue_offer_at: now])
  end

  # ============ Private ============

  defp engagement_tier_score("whale"), do: 1.0
  defp engagement_tier_score("power"), do: 0.9
  defp engagement_tier_score("active"), do: 0.7
  defp engagement_tier_score("casual"), do: 0.3
  defp engagement_tier_score(_), do: 0.1

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(v) when is_number(v), do: v / 1
  defp decimal_to_float(_), do: 0.0
end
