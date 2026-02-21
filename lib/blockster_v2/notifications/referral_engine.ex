defmodule BlocksterV2.Notifications.ReferralEngine do
  @moduledoc """
  Drives the referral system: tiered rewards, lifecycle notifications,
  leaderboard ranking, and viral loop triggers.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.{Notification, UserProfile}

  require Logger

  # ============ Reward Tiers ============

  @reward_tiers [
    %{min: 1, max: 5, referrer_bux: 500, friend_bux: 500, badge: nil, rogue: 0},
    %{min: 6, max: 15, referrer_bux: 750, friend_bux: 500, badge: "ambassador", rogue: 0},
    %{min: 16, max: 30, referrer_bux: 1000, friend_bux: 750, badge: "ambassador", rogue: 1.0},
    %{min: 31, max: 50, referrer_bux: 1500, friend_bux: 1000, badge: "vip_referrer", rogue: 1.0},
    %{min: 51, max: 999_999, referrer_bux: 2000, friend_bux: 1000, badge: "blockster_legend", rogue: 0.5}
  ]

  @doc """
  Get the reward tier for a given number of referrals converted.
  Returns the tier map with reward amounts.
  """
  def get_reward_tier(referrals_converted) when is_integer(referrals_converted) do
    Enum.find(@reward_tiers, List.first(@reward_tiers), fn tier ->
      referrals_converted >= tier.min and referrals_converted <= tier.max
    end)
  end

  @doc """
  Calculate rewards for a new referral conversion.
  Returns {referrer_bux, friend_bux, referrer_rogue_bonus} tuple.
  """
  def calculate_referral_reward(referrer_referral_count) do
    tier = get_reward_tier(referrer_referral_count)
    {tier.referrer_bux, tier.friend_bux, tier.rogue}
  end

  @doc """
  Get the badge unlocked at a given referral count, or nil if none newly unlocked.
  """
  def badge_at_count(count) do
    current_tier = get_reward_tier(count)
    prev_tier = if count > 1, do: get_reward_tier(count - 1), else: %{badge: nil}

    if current_tier.badge && current_tier.badge != prev_tier.badge do
      current_tier.badge
    else
      nil
    end
  end

  @doc """
  Get how many more referrals needed to reach the next tier.
  Returns {next_tier_min, remaining} or :max_tier.
  """
  def next_tier_info(referrals_converted) do
    current = get_reward_tier(referrals_converted)
    next_tier = Enum.find(@reward_tiers, fn t -> t.min > current.max end)

    if next_tier do
      {next_tier.min, next_tier.min - referrals_converted}
    else
      :max_tier
    end
  end

  # ============ Referral Lifecycle Notifications ============

  @doc """
  Fire notification when a referred friend signs up.
  """
  def notify_referral_signup(referrer_id, friend_name, referrals_converted) do
    {referrer_bux, _friend_bux, _rogue} = calculate_referral_reward(referrals_converted)
    badge = badge_at_count(referrals_converted)
    next_info = next_tier_info(referrals_converted)

    body =
      case next_info do
        {next_min, remaining} ->
          "You earned #{referrer_bux} BUX! #{remaining} more referral#{if remaining != 1, do: "s"} to reach the next reward tier."

        :max_tier ->
          "You earned #{referrer_bux} BUX! You're at the highest tier — keep going!"
      end

    attrs = %{
      type: "referral_signup",
      category: "social",
      title: "Your friend #{friend_name} just joined Blockster! +#{referrer_bux} BUX",
      body: body,
      action_url: "/referrals",
      action_label: "Share Again",
      metadata: %{
        friend_name: friend_name,
        bux_earned: referrer_bux,
        referrals_converted: referrals_converted,
        badge_unlocked: badge
      }
    }

    Notifications.create_notification(referrer_id, attrs)
  end

  @doc """
  Fire notification when a referred friend earns their first BUX.
  """
  def notify_referral_first_bux(referrer_id, friend_name) do
    Notifications.create_notification(referrer_id, %{
      type: "referral_reward",
      category: "social",
      title: "#{friend_name} earned their first BUX!",
      body: "Looks like they're hooked! Your referral is paying off.",
      metadata: %{
        milestone: "first_bux",
        friend_name: friend_name
      }
    })
  end

  @doc """
  Fire notification when a referred friend makes their first purchase.
  Includes 200 BUX bonus to referrer.
  """
  def notify_referral_first_purchase(referrer_id, friend_name) do
    Notifications.create_notification(referrer_id, %{
      type: "referral_reward",
      category: "social",
      title: "#{friend_name} just made their first purchase!",
      body: "As a thank you for a quality referral, here's an extra 200 BUX bonus.",
      metadata: %{
        milestone: "first_purchase",
        friend_name: friend_name,
        bonus_bux: 200
      }
    })
  end

  @doc """
  Fire notification when a referred friend plays their first game.
  """
  def notify_referral_first_game(referrer_id, friend_name) do
    Notifications.create_notification(referrer_id, %{
      type: "referral_reward",
      category: "social",
      title: "#{friend_name} just tried BUX Booster!",
      body: "Refer 2 more friends who play and get 1 free ROGUE.",
      action_url: "/referrals",
      action_label: "Share With Friends",
      metadata: %{
        milestone: "first_game",
        friend_name: friend_name
      }
    })
  end

  # ============ Leaderboard ============

  @doc """
  Get the referral leaderboard for the current week.
  Returns [{user_id, username, referral_count, bux_earned}] sorted by referrals desc.
  """
  def weekly_leaderboard(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    week_start = current_week_start()

    from(u in BlocksterV2.Accounts.User,
      join: p in UserProfile, on: p.user_id == u.id,
      where: p.referrals_converted > 0,
      order_by: [desc: p.referrals_converted],
      limit: ^limit,
      select: %{
        user_id: u.id,
        username: u.username,
        referrals_converted: p.referrals_converted,
        referral_propensity: p.referral_propensity
      }
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} ->
      tier = get_reward_tier(entry.referrals_converted)
      bux_earned = entry.referrals_converted * tier.referrer_bux

      Map.merge(entry, %{
        rank: rank,
        bux_earned: bux_earned
      })
    end)
  end

  @doc """
  Get a specific user's position on the leaderboard.
  Returns {rank, total_users} or nil if no referrals.
  """
  def user_leaderboard_position(user_id) do
    profile = BlocksterV2.UserEvents.get_profile(user_id)

    if profile && (profile.referrals_converted || 0) > 0 do
      users_ahead =
        from(p in UserProfile,
          where: p.referrals_converted > ^profile.referrals_converted,
          where: p.user_id != ^user_id
        )
        |> Repo.aggregate(:count, :id)

      total =
        from(p in UserProfile,
          where: p.referrals_converted > 0
        )
        |> Repo.aggregate(:count, :id)

      {users_ahead + 1, total}
    else
      nil
    end
  end

  # ============ Referral Prompt Helpers ============

  @doc """
  Get contextual referral message for insertion into emails.
  """
  def referral_block_for_email(email_type, profile) do
    referrals = if profile, do: profile.referrals_converted || 0, else: 0
    tier = get_reward_tier(max(referrals + 1, 1))

    case email_type do
      "daily_digest" ->
        %{
          heading: "Share the knowledge",
          message: "Invite friends and earn #{tier.referrer_bux} BUX each",
          cta: "Share Your Link"
        }

      "reward_summary" ->
        %{
          heading: "Your friends can earn too",
          message: "You earned BUX this week — share the love and earn #{tier.referrer_bux} BUX per referral",
          cta: "Invite Friends"
        }

      "bux_milestone" ->
        %{
          heading: "Celebrate together",
          message: "Share Blockster and earn even more BUX",
          cta: "Share & Earn"
        }

      "game_result" ->
        %{
          heading: "Share your win!",
          message: "Refer friends who play = free ROGUE",
          cta: "Refer a Player"
        }

      "order_confirmation" ->
        %{
          heading: "Love your purchase?",
          message: "Friends get a head start with #{tier.friend_bux} BUX when they join",
          cta: "Share With Friends"
        }

      "cart_abandonment" ->
        %{
          heading: "While you decide...",
          message: "Tell a friend about Blockster and earn #{tier.referrer_bux} BUX",
          cta: "Share Your Link"
        }

      _ ->
        %{
          heading: "Invite friends, earn together",
          message: "Get #{tier.referrer_bux} BUX for every friend who joins",
          cta: "Share Your Link"
        }
    end
  end

  @doc """
  Check if a user should receive a referral prompt right now.
  Accounts for fatigue and recent prompts.
  """
  def should_prompt_referral?(user_id, profile) do
    propensity = if profile, do: profile.referral_propensity || 0.0, else: 0.0

    cond do
      # Always prompt high-propensity users
      propensity > 0.7 ->
        !sent_referral_prompt_this_week?(user_id)

      # Prompt active users with moderate propensity less frequently
      propensity > 0.3 ->
        !sent_referral_prompt_this_month?(user_id)

      # Don't prompt low-propensity users
      true ->
        false
    end
  end

  # ============ Private Helpers ============

  defp current_week_start do
    Date.utc_today()
    |> Date.beginning_of_week(:monday)
    |> NaiveDateTime.new!(~T[00:00:00])
  end

  defp sent_referral_prompt_this_week?(user_id) do
    since = current_week_start()

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "referral_prompt",
      where: n.inserted_at >= ^since
    )
    |> Repo.exists?()
  end

  defp sent_referral_prompt_this_month?(user_id) do
    since =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-30 * 86400, :second)

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "referral_prompt",
      where: n.inserted_at >= ^since
    )
    |> Repo.exists?()
  end
end
