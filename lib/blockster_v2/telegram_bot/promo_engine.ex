defmodule BlocksterV2.TelegramBot.PromoEngine do
  @moduledoc """
  Central module for the hourly promo system.
  Manages promo template library, weighted selection, activation/settlement.
  Enforces daily BUX budget (100,000/day) and per-user reward limits (10/day).
  """
  require Logger

  alias BlocksterV2.{BuxMinter, Repo}
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Notifications.SystemConfig
  import Ecto.Query

  @daily_bux_limit 100_000
  @max_rewards_per_user_per_day 10

  # ======== Promo Types ========

  @promo_weights [
    {:bux_booster_rule, 35},
    {:referral_boost, 25},
    {:giveaway, 20},
    {:competition, 20}
  ]

  # ======== BUX Booster Rule Templates ========

  # ======== Rule Template Design Principles ========
  #
  # Reward amount is based on max(payout - bet_amount, bet_amount - payout) i.e. abs(profit):
  #   - On a WIN:  profit = payout - bet_amount. Always positive since mult >= 1.02.
  #                1.02x on 1000 = profit 20 → tiny bonus. 31.68x on 1000 = profit 30680 → huge.
  #   - On a LOSS: payout = 0, so bet_amount - payout = bet_amount. Bonus on stake.
  #
  # No fixed cap — reward is purely percentage-based.
  # Daily budget (100,000 BUX) and per-user limit (10/day) provide system-level caps.
  #
  # ROGUE balance affects:
  #   1. Trigger FREQUENCY via every_n_formula — more ROGUE = triggers more often
  #      Divisors scaled for 100k–2M ROGUE range (e.g. /250000, /150000)
  #   2. Small flat bonus: 0.01% of rogue_balance added to each reward
  #      (100k = 10 BUX, 500k = 50, 1M = 100, 2M = 200)
  #
  # No win-rate conditions — different games have different probabilities.
  #
  # Available per-bet metadata from game_played event:
  #   bet_amount    — BUX wagered on THIS bet
  #   payout        — winnings (bet * multiplier on win, 0 on loss)
  #   rogue_balance — current ROGUE token balance
  #   total_bets    — lifetime bet count (used as count_field for recurring)

  @rule_templates [
    %{
      name: "Bet Bonus Blitz",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "Bet Bonus hit!",
        "body" => "Your bet just earned you bonus BUX!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # 20% of profit (wins) or stake (losses), no fixed cap
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * 0.2 + rogue_balance * 0.0001",
        "recurring" => true,
        "every_n_formula" => "max(6 - min(rogue_balance / 250000, 4), 2)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🎰 BET BONUS BLITZ!</b>\n\nFor the next 60 minutes, random BUX Booster bets earn you <b>20% bonus BUX</b>!\n\n<b>How it works:</b>\n• Win? 20% of your profit\n• Lose? 20% of your stake\n\n<b>1000 BUX stake examples:</b>\n• 1.02x win (profit 20) → <b>4 BUX</b>\n• 1.05x win (profit 50) → <b>10 BUX</b>\n• 1.13x win (profit 130) → <b>26 BUX</b>\n• 1.32x win (profit 320) → <b>64 BUX</b>\n• 1.98x win (profit 980) → <b>196 BUX</b>\n• 3.96x win (profit 2,960) → <b>592 BUX</b>\n• 7.92x win (profit 6,920) → <b>1,384 BUX</b>\n• 15.84x win (profit 14,840) → <b>2,968 BUX</b>\n• 31.68x win (profit 30,680) → <b>6,136 BUX</b>\n• Loss → <b>200 BUX</b>\n\n💎 <b>Hold ROGUE to trigger more often:</b>\n• 0 ROGUE → every ~6 bets\n• 500k ROGUE → every ~4 bets\n• 1M+ ROGUE → every ~2 bets\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "Safety Net Hour",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "Safety Net activated!",
        "body" => "Bonus BUX from Safety Net — keep playing!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # 30% — higher payout but triggers less often for non-holders
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * 0.3 + rogue_balance * 0.0001",
        "recurring" => true,
        "every_n_formula" => "max(8 - min(rogue_balance / 200000, 5), 3)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🛡️ SAFETY NET HOUR!</b>\n\nRandom BUX Booster bets earn you <b>30% bonus BUX</b> — your insurance policy!\n\n<b>How it works:</b>\n• Win? 30% of your profit\n• Lose? 30% of your stake comes back as BUX\n\n<b>1000 BUX stake examples:</b>\n• 1.02x win (profit 20) → <b>6 BUX</b>\n• 1.05x win (profit 50) → <b>15 BUX</b>\n• 1.13x win (profit 130) → <b>39 BUX</b>\n• 1.32x win (profit 320) → <b>96 BUX</b>\n• 1.98x win (profit 980) → <b>294 BUX</b>\n• 3.96x win (profit 2,960) → <b>888 BUX</b>\n• 7.92x win (profit 6,920) → <b>2,076 BUX</b>\n• 15.84x win (profit 14,840) → <b>4,452 BUX</b>\n• 31.68x win (profit 30,680) → <b>9,204 BUX</b>\n• Loss → <b>300 BUX</b>\n\n💎 <b>ROGUE holders trigger more often:</b>\n• 0 ROGUE → every ~8 bets\n• 400k ROGUE → every ~6 bets\n• 1M+ ROGUE → every ~3 bets\n\n<b>Even a bad session can break even with these bonuses.</b>\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "ROGUE Holders Hour",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "ROGUE Holder bonus!",
        "body" => "Your ROGUE bag just earned you extra BUX!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # 15% — lower per-hit but most aggressive frequency for holders
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * 0.15 + rogue_balance * 0.0001",
        "recurring" => true,
        # ROGUE holders get very frequent triggers (every 1-5 bets)
        "every_n_formula" => "max(5 - min(rogue_balance / 150000, 4), 1)",
        "count_field" => "total_bets"
      },
      announcement: "<b>💎 ROGUE HOLDERS HOUR!</b>\n\nThis one's for ROGUE holders — <b>15% bonus BUX</b> and the more ROGUE you hold, the more often it triggers!\n\n<b>How it works:</b>\n• Win? 15% of your profit\n• Lose? 15% of your stake\n\n<b>1000 BUX stake examples:</b>\n• 1.02x win (profit 20) → <b>3 BUX</b>\n• 1.05x win (profit 50) → <b>7 BUX</b>\n• 1.13x win (profit 130) → <b>19 BUX</b>\n• 1.32x win (profit 320) → <b>48 BUX</b>\n• 1.98x win (profit 980) → <b>147 BUX</b>\n• 3.96x win (profit 2,960) → <b>444 BUX</b>\n• 7.92x win (profit 6,920) → <b>1,038 BUX</b>\n• 15.84x win (profit 14,840) → <b>2,226 BUX</b>\n• 31.68x win (profit 30,680) → <b>4,602 BUX</b>\n• Loss → <b>150 BUX</b>\n\n💎 <b>Trigger frequency:</b>\n• 0 ROGUE → every ~5 bets\n• 300k ROGUE → every ~3 bets\n• 600k+ ROGUE → almost every bet!\n\n<b>Lower bonus per hit, but it stacks up fast.</b> Hold ROGUE, stack BUX.\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "High Roller Hour",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "High Roller bonus!",
        "body" => "Big bet = big bonus BUX!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # 25% — only fires on bets >= 500 BUX
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * 0.25 + rogue_balance * 0.0001",
        "conditions" => %{"bet_amount" => %{"$gte" => 500}},
        "recurring" => true,
        "every_n_formula" => "max(5 - min(rogue_balance / 300000, 3), 2)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🐋 HIGH ROLLER HOUR!</b>\n\nBUX Booster stakes of <b>500+ BUX</b> earn you <b>25% bonus BUX</b>!\n\n<b>How it works:</b>\n• Win? 25% of your profit\n• Lose? 25% of your stake\n• Stakes under 500 BUX don't qualify\n\n<b>1000 BUX stake examples:</b>\n• 1.02x win (profit 20) → <b>5 BUX</b>\n• 1.05x win (profit 50) → <b>12 BUX</b>\n• 1.13x win (profit 130) → <b>32 BUX</b>\n• 1.32x win (profit 320) → <b>80 BUX</b>\n• 1.98x win (profit 980) → <b>245 BUX</b>\n• 3.96x win (profit 2,960) → <b>740 BUX</b>\n• 7.92x win (profit 6,920) → <b>1,730 BUX</b>\n• 15.84x win (profit 14,840) → <b>3,710 BUX</b>\n• 31.68x win (profit 30,680) → <b>7,670 BUX</b>\n• Loss → <b>250 BUX</b>\n\n💎 <b>ROGUE holders trigger more often:</b>\n• 0 ROGUE → every ~5 big bets\n• 600k ROGUE → every ~3 big bets\n• 900k+ ROGUE → every ~2 big bets\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "Lucky Streak",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "Lucky Streak hit!",
        "body" => "The lucky streak has blessed your bet!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # Random 10-50% — both amount AND frequency are random
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * random(10, 50) * 0.01 + rogue_balance * 0.0001",
        "recurring" => true,
        "every_n_formula" => "max(random(3, 7) - min(rogue_balance / 400000, 3), 2)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🍀 LUCKY STREAK!</b>\n\nRandom BUX Booster bets earn you a <b>random 10-50%</b> bonus!\n\n<b>How it works:</b>\n• Win? 10-50% of your profit\n• Lose? 10-50% of your stake\n• Both the bonus % AND how often it triggers are random\n\n<b>1000 BUX stake — all wins at 30% roll:</b>\n• 1.02x (profit 20) → <b>6 BUX</b>\n• 1.05x (profit 50) → <b>15 BUX</b>\n• 1.13x (profit 130) → <b>39 BUX</b>\n• 1.32x (profit 320) → <b>96 BUX</b>\n• 1.98x (profit 980) → <b>294 BUX</b>\n• 3.96x (profit 2,960) → <b>888 BUX</b>\n• 7.92x (profit 6,920) → <b>2,076 BUX</b>\n• 15.84x (profit 14,840) → <b>4,452 BUX</b>\n• 31.68x (profit 30,680) → <b>9,204 BUX</b>\n• Loss → <b>100-500 BUX</b>\n\n💎 <b>ROGUE holders get luckier:</b>\n• More ROGUE = more frequent triggers\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "Newbie Power Hour",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "Newbie Power Hour bonus!",
        "body" => "Welcome bonus — keep playing to earn more!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # Generous 40% for newbies, no fixed cap
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * 0.4 + rogue_balance * 0.0001",
        "conditions" => %{"total_bets" => %{"$lte" => 20}},
        "recurring" => true,
        "every_n_formula" => "max(4 - min(rogue_balance / 250000, 2), 2)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🌟 NEWBIE POWER HOUR!</b>\n\nFirst 20 BUX Booster bets? You're getting <b>40% bonus BUX</b> on random bets!\n\n<b>How it works:</b>\n• Win? 40% of your profit\n• Lose? 40% of your stake comes back as BUX\n\n<b>200 BUX stake examples:</b>\n• 1.02x win (profit 4) → <b>1 BUX</b>\n• 1.05x win (profit 10) → <b>4 BUX</b>\n• 1.13x win (profit 26) → <b>10 BUX</b>\n• 1.32x win (profit 64) → <b>25 BUX</b>\n• 1.98x win (profit 196) → <b>78 BUX</b>\n• 3.96x win (profit 592) → <b>236 BUX</b>\n• 7.92x win (profit 1,384) → <b>553 BUX</b>\n• 15.84x win (profit 2,968) → <b>1,187 BUX</b>\n• 31.68x win (profit 6,136) → <b>2,454 BUX</b>\n• Loss → <b>80 BUX</b>\n\n💎 <b>Hold some ROGUE to trigger even more often!</b>\n\n<b>New here? This is your chance.</b> Try different games — the bonuses keep you in the game.\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    },
    %{
      name: "Mystery Jackpot",
      category: :bux_booster_rule,
      rule: %{
        "event_type" => "game_played",
        "action" => "notification",
        "title" => "MYSTERY JACKPOT!",
        "body" => "You hit a mystery jackpot on your bet!",
        "channel" => "in_app",
        "notification_type" => "promo_reward",
        "action_url" => "/play",
        "action_label" => "Keep Playing",
        # 50-100% — rare but massive
        "bux_bonus_formula" => "max(payout - bet_amount, bet_amount - payout) * random(50, 100) * 0.01 + rogue_balance * 0.0001",
        "recurring" => true,
        # Rare: every 4-10 bets, ROGUE compresses the range
        "every_n_formula" => "max(random(6, 10) - min(rogue_balance / 250000, 4), 4)",
        "count_field" => "total_bets"
      },
      announcement: "<b>🎲 MYSTERY JACKPOT!</b>\n\nRare jackpots are active on BUX Booster — when one hits, you earn <b>50-100%</b> bonus BUX!\n\n<b>How it works:</b>\n• Win? 50-100% of your profit\n• Lose? 50-100% of your stake as a jackpot consolation\n• Triggers are rare, but when they hit — massive\n\n<b>1000 BUX stake — all wins at 75% roll:</b>\n• 1.02x (profit 20) → <b>15 BUX</b>\n• 1.05x (profit 50) → <b>37 BUX</b>\n• 1.13x (profit 130) → <b>97 BUX</b>\n• 1.32x (profit 320) → <b>240 BUX</b>\n• 1.98x (profit 980) → <b>735 BUX</b>\n• 3.96x (profit 2,960) → <b>2,220 BUX</b>\n• 7.92x (profit 6,920) → <b>5,190 BUX</b>\n• 15.84x (profit 14,840) → <b>11,130 BUX</b>\n• 31.68x (profit 30,680) → <b>23,010 BUX</b>\n• Loss (75% roll) → <b>750 BUX</b>\n\n💎 <b>ROGUE holders hit jackpots more often:</b>\n• 0 ROGUE → every ~10 bets\n• 500k ROGUE → every ~6 bets\n• 1M+ ROGUE → every ~4 bets\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
    }
  ]

  # ======== Referral Boost Templates ========

  @referral_templates [
    %{
      name: "Double Referral Hour",
      category: :referral_boost,
      boost: %{referrer_signup_bux: 1000, referee_signup_bux: 500, phone_verify_bux: 1000},
      original: %{referrer_signup_bux: 500, referee_signup_bux: 250, phone_verify_bux: 500},
      announcement: "<b>🔥 DOUBLE REFERRAL HOUR!</b>\n\nFor the next <b>60 minutes only</b>, referral bonuses are DOUBLED:\n\n✅ You get <b>1,000 BUX</b> (normally 500)\n✅ Your friend gets <b>500 BUX</b> (normally 250)\n✅ Phone verify bonus: <b>1,000 BUX</b> (normally 500)\n\nShare your referral link NOW!\n\n⏰ This offer expires in 60 minutes!\n👉 <a href=\"https://blockster.com/notifications/referrals\">Get Your Referral Link</a>"
    },
    %{
      name: "Triple Threat Referral",
      category: :referral_boost,
      boost: %{referrer_signup_bux: 1500, referee_signup_bux: 750, phone_verify_bux: 1500},
      original: %{referrer_signup_bux: 500, referee_signup_bux: 250, phone_verify_bux: 500},
      announcement: "<b>⚡ TRIPLE THREAT REFERRAL!</b>\n\nFor the next <b>60 minutes only</b>, referral bonuses are TRIPLED:\n\n✅ You get <b>1,500 BUX</b> (normally 500)\n✅ Your friend gets <b>750 BUX</b> (normally 250)\n✅ Phone verify bonus: <b>1,500 BUX</b> (normally 500)\n\nThis is the biggest referral bonus ever!\n\n⏰ This offer expires in 60 minutes!\n👉 <a href=\"https://blockster.com/notifications/referrals\">Get Your Referral Link</a>"
    },
    %{
      name: "Mega Referral Hour",
      category: :referral_boost,
      boost: %{referrer_signup_bux: 1000, referee_signup_bux: 500, phone_verify_bux: 1000},
      original: %{referrer_signup_bux: 500, referee_signup_bux: 250, phone_verify_bux: 500},
      announcement: "<b>💎 MEGA REFERRAL HOUR!</b>\n\n2x signup + 2x phone verify + guaranteed welcome bonus!\n\n✅ Referrer: <b>1,000 BUX</b>\n✅ New user: <b>500 BUX</b>\n✅ Phone verify: <b>1,000 BUX</b>\n\nTell your friends — this is their best chance to start earning!\n\n⏰ 60 minutes only!\n👉 <a href=\"https://blockster.com/notifications/referrals\">Get Your Referral Link</a>"
    }
  ]

  # ======== Giveaway Templates ========

  @giveaway_templates [
    %{
      name: "BUX Rain",
      category: :giveaway,
      type: :activity_based,
      event_type: "article_view",
      winner_count: 5,
      prize_range: {100, 500},
      announcement: "<b>🌧️ BUX RAIN!</b>\n\nRandom BUX airdrop to active readers!\n\n<b>How to enter:</b>\n• Read any article on blockster.com in the next 60 minutes\n• 5 lucky readers will be randomly selected\n• Win 100-500 BUX each!\n\n⏰ <b>Drawing in 60 minutes</b>\n👉 <a href=\"https://blockster.com\">Start Reading</a>"
    },
    %{
      name: "Snapshot Giveaway",
      category: :giveaway,
      type: :auto_entry,
      winner_count: 3,
      prize_range: {250, 400},
      announcement: "<b>📸 SNAPSHOT GIVEAWAY!</b>\n\nAll linked Telegram group members are automatically entered!\n\n🏆 3 winners will be drawn\n💰 1,000 BUX total prize pool\n\nNo action needed — just being in the group gives you a chance!\n\n⏰ <b>Drawing in 60 minutes</b>\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
    },
    %{
      name: "New Member Welcome Drop",
      category: :giveaway,
      type: :new_members,
      prize_amount: 1000,
      announcement: "<b>👋 NEW MEMBER WELCOME DROP!</b>\n\nAnyone who joined the group in the last hour gets <b>1,000 BUX</b>!\n\nKnow someone who should join? Tell them NOW:\n👉 <a href=\"https://t.me/+7bIzOyrYBEc3OTdh\">Join the Blockster Group</a>\n\n⏰ <b>Ends in 60 minutes</b>"
    }
  ]

  # ======== Competition Templates ========

  @competition_templates [
    %{
      name: "Most Articles Read",
      category: :competition,
      metric: :articles_read,
      event_type: "article_view",
      prize_pool: 1500,
      distribution: :tiered,
      top_n: 3,
      announcement: "<b>🏆 HOURLY CONTEST: Reading Champion!</b>\n\nThe reader who finishes the most articles in the next 60 minutes wins:\n\n🥇 1st Place: <b>750 BUX</b>\n🥈 2nd Place: <b>450 BUX</b>\n🥉 3rd Place: <b>300 BUX</b>\n\n⏰ <b>Competition ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com\">Start Reading</a>"
    },
    %{
      name: "Bet Count Champion",
      category: :competition,
      metric: :bet_count,
      event_type: "game_played",
      prize_pool: 1500,
      distribution: :tiered,
      top_n: 3,
      announcement: "<b>🏆 HOURLY CONTEST: Bet Count Champion!</b>\n\nThe player with the most bets in the next 60 minutes wins:\n\n🥇 1st Place: <b>750 BUX</b>\n🥈 2nd Place: <b>450 BUX</b>\n🥉 3rd Place: <b>300 BUX</b>\n\n⏰ <b>Competition ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Start Playing</a>"
    }
  ]

  # ======== Public API ========

  @doc "Get all available promo templates by category"
  def all_templates do
    %{
      bux_booster_rule: @rule_templates,
      referral_boost: @referral_templates,
      giveaway: @giveaway_templates,
      competition: @competition_templates
    }
  end

  @doc "Pick the next promo based on weighted random selection + history constraints"
  def pick_next_promo(history \\ []) do
    category = pick_category(history)
    template = pick_template(category, history)

    promo_id = "promo_#{System.system_time(:millisecond)}"

    %{
      id: promo_id,
      category: category,
      template: template,
      name: template.name,
      announcement_html: get_announcement(template),
      started_at: DateTime.utc_now(),
      expires_at: DateTime.utc_now() |> DateTime.add(3600, :second),
      results: nil
    }
  end

  @doc "Activate a promo (create custom rules, boost rates, etc.)"
  def activate_promo(%{category: :bux_booster_rule, template: template} = promo) do
    rule = template.rule
      |> Map.put("_hourly_promo", true)
      |> Map.put("_promo_id", promo.id)
      |> Map.put("_expires_at", DateTime.to_iso8601(promo.expires_at))
      |> Map.put("source", "telegram_bot")

    rules = SystemConfig.get("custom_rules", [])
    SystemConfig.put("custom_rules", rules ++ [rule], "hourly_promo_bot")

    Logger.info("[PromoEngine] Activated BUX Booster rule: #{template.name}")
    :ok
  end

  def activate_promo(%{category: :referral_boost, template: template} = _promo) do
    # Store original values before boosting
    original = template.original
    boost = template.boost

    # Save originals so we can restore them
    :mnesia.dirty_write({:hourly_promo_state, :referral_originals,
      %{
        referrer_signup_bux: SystemConfig.get("referrer_signup_bux", original.referrer_signup_bux),
        referee_signup_bux: SystemConfig.get("referee_signup_bux", original.referee_signup_bux),
        phone_verify_bux: SystemConfig.get("phone_verify_bux", original.phone_verify_bux)
      },
      DateTime.utc_now(), nil})

    # Apply boosted rates
    SystemConfig.put("referrer_signup_bux", boost.referrer_signup_bux, "hourly_promo_bot")
    SystemConfig.put("referee_signup_bux", boost.referee_signup_bux, "hourly_promo_bot")
    SystemConfig.put("phone_verify_bux", boost.phone_verify_bux, "hourly_promo_bot")

    Logger.info("[PromoEngine] Activated referral boost: #{template.name}")
    :ok
  end

  def activate_promo(%{category: category} = promo) when category in [:giveaway, :competition] do
    # For reading/social promos with rules, activate the custom rule
    if template_rule = promo.template[:rule] do
      rule = template_rule
        |> Map.put("_hourly_promo", true)
        |> Map.put("_promo_id", promo.id)
        |> Map.put("_expires_at", DateTime.to_iso8601(promo.expires_at))
        |> Map.put("source", "telegram_bot")

      rules = SystemConfig.get("custom_rules", [])
      SystemConfig.put("custom_rules", rules ++ [rule], "hourly_promo_bot")
    end

    Logger.info("[PromoEngine] Activated #{category}: #{promo.name}")
    :ok
  end

  @doc "Settle/deactivate a promo (remove custom rules, restore rates, pay winners)"
  def settle_promo(nil), do: :ok

  def settle_promo(%{category: :bux_booster_rule} = promo) do
    cleanup_hourly_rules(promo.id)
    Logger.info("[PromoEngine] Settled BUX Booster rule: #{promo.name}")
    :ok
  end

  def settle_promo(%{category: :referral_boost} = promo) do
    # Restore original referral rates
    case :mnesia.dirty_read(:hourly_promo_state, :referral_originals) do
      [{:hourly_promo_state, :referral_originals, originals, _, _}] ->
        SystemConfig.put("referrer_signup_bux", originals.referrer_signup_bux, "hourly_promo_bot")
        SystemConfig.put("referee_signup_bux", originals.referee_signup_bux, "hourly_promo_bot")
        SystemConfig.put("phone_verify_bux", originals.phone_verify_bux, "hourly_promo_bot")
        :mnesia.dirty_delete(:hourly_promo_state, :referral_originals)

      _ ->
        # Fallback — restore defaults
        SystemConfig.put("referrer_signup_bux", 500, "hourly_promo_bot")
        SystemConfig.put("referee_signup_bux", 250, "hourly_promo_bot")
        SystemConfig.put("phone_verify_bux", 500, "hourly_promo_bot")
    end

    Logger.info("[PromoEngine] Settled referral boost: #{promo.name}")
    :ok
  end

  def settle_promo(%{category: :giveaway} = promo) do
    results = settle_giveaway(promo)
    cleanup_hourly_rules(promo.id)
    Logger.info("[PromoEngine] Settled giveaway: #{promo.name}")
    results
  end

  def settle_promo(%{category: :competition} = promo) do
    results = settle_competition(promo)
    cleanup_hourly_rules(promo.id)
    Logger.info("[PromoEngine] Settled competition: #{promo.name}")
    results
  end


  @doc "Format results HTML for announcement"
  def format_results_html(nil, _next_promo), do: nil

  def format_results_html(%{category: :giveaway} = promo, next_promo) do
    case promo.results do
      {:ok, winners} when is_list(winners) and length(winners) > 0 ->
        winner_lines = Enum.map(winners, fn {_user_id, username, amount} ->
          name = if username, do: "@#{username}", else: "Anonymous"
          "🏆 #{name} — <b>#{trunc(amount)} BUX</b>"
        end)
        |> Enum.join("\n")

        total = Enum.reduce(winners, 0, fn {_, _, amt}, acc -> acc + amt end)

        next_line = if next_promo, do: "\n<b>Up next:</b> #{next_promo.name}!", else: ""

        "<b>🎊 GIVEAWAY WINNERS!</b>\n\n#{promo.name} results:\n\n#{winner_lines}\n\n💰 <b>#{trunc(total)} BUX</b> distributed!\n#{next_line}\n👉 <a href=\"https://blockster.com\">Join the action</a>"

      _ ->
        "<b>🎊 #{promo.name} Results</b>\n\nNo eligible participants this round. Better luck next hour!\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
    end
  end

  def format_results_html(%{category: :competition} = promo, next_promo) do
    case promo.results do
      {:ok, winners} when is_list(winners) and length(winners) > 0 ->
        medals = ["🥇", "🥈", "🥉"]
        winner_lines = winners
          |> Enum.with_index()
          |> Enum.map(fn {{_user_id, username, amount}, idx} ->
            medal = Enum.at(medals, idx, "🏅")
            name = if username, do: "@#{username}", else: "Anonymous"
            "#{medal} #{name} — <b>#{trunc(amount)} BUX</b>"
          end)
          |> Enum.join("\n")

        total = Enum.reduce(winners, 0, fn {_, _, amt}, acc -> acc + amt end)

        next_line = if next_promo, do: "\n<b>Up next:</b> #{next_promo.name}!", else: ""

        "<b>🏆 #{promo.name} RESULTS!</b>\n\n#{winner_lines}\n\n💰 <b>#{trunc(total)} BUX</b> in prizes!\n#{next_line}\n👉 <a href=\"https://blockster.com\">Join the action</a>"

      _ ->
        "<b>🏆 #{promo.name} Results</b>\n\nNo participants this round. Jump in next hour!\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
    end
  end

  def format_results_html(%{category: :bux_booster_rule} = promo, next_promo) do
    next_line = if next_promo, do: "\n<b>Up next:</b> #{next_promo.name}!", else: ""
    "<b>🎰 #{promo.name} is over!</b>\n\nThanks to everyone who played!\n#{next_line}\n👉 <a href=\"https://blockster.com\">Keep playing</a>"
  end

  def format_results_html(%{category: :referral_boost} = promo, next_promo) do
    next_line = if next_promo, do: "\n<b>Up next:</b> #{next_promo.name}!", else: ""
    "<b>🔥 #{promo.name} is over!</b>\n\nReferral bonuses are back to normal rates.\n#{next_line}\n👉 <a href=\"https://blockster.com\">Keep earning</a>"
  end

  def format_results_html(promo, next_promo) do
    next_line = if next_promo, do: "\n<b>Up next:</b> #{next_promo.name}!", else: ""
    "<b>#{promo.name} has ended!</b>\n#{next_line}\n👉 <a href=\"https://blockster.com\">Visit Blockster</a>"
  end

  # ======== Budget Enforcement ========

  @doc "Credit BUX to a user. Enforces daily budget + per-user limit."
  def credit_user(user_id, amount, reason \\ :ai_bonus) do
    with :ok <- check_daily_budget(amount),
         :ok <- check_user_reward_limit(user_id) do
      user = Repo.get(User, user_id)

      if user && user.smart_wallet_address do
        case BuxMinter.mint_bux(user.smart_wallet_address, amount, user_id, nil, reason) do
          {:ok, _} ->
            record_reward(user_id, amount)
            BuxMinter.sync_user_balances_async(user_id, user.smart_wallet_address, force: true)
            {:ok, amount}

          error ->
            error
        end
      else
        {:error, :no_wallet}
      end
    end
  end

  @doc "Credit multiple users (for giveaway/competition payouts)"
  def credit_users(user_amounts, reason \\ :ai_bonus) do
    Enum.map(user_amounts, fn {user_id, amount} ->
      Process.sleep(100)
      {user_id, credit_user(user_id, amount, reason)}
    end)
  end

  @doc "Get today's budget state"
  def get_daily_state do
    get_or_reset_daily_state()
  end

  @doc "Get remaining BUX budget for today"
  def remaining_budget do
    state = get_or_reset_daily_state()
    max(@daily_bux_limit - state.total_bux_given, 0)
  end

  @doc "Check if the budget is exhausted"
  def budget_exhausted? do
    remaining_budget() <= 0
  end

  # ======== Private Helpers ========

  defp pick_category(history) do
    recent_categories = Enum.map(history, & &1.category) |> Enum.take(4)

    # Apply deduplication rules
    weights = @promo_weights
      |> apply_dedup_rules(recent_categories)
      |> apply_guaranteed_minimums(recent_categories)

    weighted_random(weights)
  end

  defp apply_dedup_rules(weights, recent_categories) do
    last_category = List.first(recent_categories)
    last_two = Enum.take(recent_categories, 2)

    Enum.map(weights, fn {category, weight} ->
      cond do
        # Max 2 of same category in a row
        length(last_two) == 2 and Enum.all?(last_two, &(&1 == category)) ->
          {category, 0}

        # Competition always alternates with non-competition
        category == :competition and last_category == :competition ->
          {category, 0}

        # Slight penalty for same as last
        category == last_category ->
          {category, div(weight, 2)}

        true ->
          {category, weight}
      end
    end)
  end

  defp apply_guaranteed_minimums(weights, recent_categories) do
    recent_4 = Enum.take(recent_categories, 4)
    recent_3 = Enum.take(recent_categories, 3)

    weights
    |> Enum.map(fn {category, weight} ->
      cond do
        # Referral at least every 4 hours
        category == :referral_boost and length(recent_4) >= 3 and category not in recent_4 ->
          {category, max(weight, 50)}

        # BUX Booster at least every 3 hours
        category == :bux_booster_rule and length(recent_3) >= 2 and category not in recent_3 ->
          {category, max(weight, 50)}

        true ->
          {category, weight}
      end
    end)
  end

  defp pick_template(category, history) do
    templates = case category do
      :bux_booster_rule -> @rule_templates
      :referral_boost -> @referral_templates
      :giveaway -> @giveaway_templates
      :competition -> @competition_templates
    end

    last_name = case history do
      [%{name: name} | _] -> name
      _ -> nil
    end

    # Filter out the last used template (no exact repeats)
    candidates = Enum.reject(templates, &(&1.name == last_name))
    candidates = if candidates == [], do: templates, else: candidates

    Enum.random(candidates)
  end

  @bux_booster_footer "\n\n💡 <b>Pro tip:</b> Bonus is based on your profit (wins) or your stake (losses). Higher multiplier games = bigger profits = bigger bonuses. Hold more ROGUE to trigger more often!"

  defp get_announcement(%{announcement: nil, name: name, category: :bux_booster_rule}) do
    "<b>🎰 #{name}!</b>\n\nSpecial BUX Booster promo active for the next 60 minutes!#{@bux_booster_footer}\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com/play\">Play Now</a>"
  end

  defp get_announcement(%{announcement: nil, name: name, category: category}) do
    "<b>#{category_emoji(category)} #{name}!</b>\n\nSpecial promo active for the next 60 minutes!\n\n⏰ <b>Ends in 60 minutes</b>\n👉 <a href=\"https://blockster.com\">Join the action</a>"
  end

  defp get_announcement(%{announcement: html, category: :bux_booster_rule}) do
    # Ensure BUX Booster announcements always remind about bet size + ROGUE scaling
    if String.contains?(html, "ROGUE") do
      html
    else
      html <> @bux_booster_footer
    end
  end

  defp get_announcement(%{announcement: html}), do: html

  defp category_emoji(:bux_booster_rule), do: "🎰"
  defp category_emoji(:referral_boost), do: "🔥"
  defp category_emoji(:giveaway), do: "🎊"
  defp category_emoji(:competition), do: "🏆"

  defp weighted_random(weights) do
    total = Enum.reduce(weights, 0, fn {_, w}, acc -> acc + w end)

    if total == 0 do
      # All weights are 0, pick from defaults
      {category, _} = Enum.random(@promo_weights)
      category
    else
      target = :rand.uniform(total)
      pick_weighted(weights, target, 0)
    end
  end

  defp pick_weighted([{category, weight} | rest], target, acc) do
    new_acc = acc + weight
    if new_acc >= target, do: category, else: pick_weighted(rest, target, new_acc)
  end

  defp pick_weighted([], _target, _acc) do
    # Fallback
    :bux_booster_rule
  end

  # ======== Giveaway Settlement ========

  defp settle_giveaway(%{template: %{type: :auto_entry, winner_count: count, prize_range: {min_prize, max_prize}}}) do
    eligible = get_eligible_group_members()

    if length(eligible) > 0 do
      winners = eligible
        |> Enum.take_random(min(count, length(eligible)))
        |> Enum.map(fn user ->
          amount = min_prize + :rand.uniform(max_prize - min_prize)
          {user.id, user.telegram_username, amount}
        end)

      # Credit winners
      Enum.each(winners, fn {user_id, _username, amount} ->
        credit_user(user_id, amount)
        Process.sleep(100)
      end)

      {:ok, winners}
    else
      {:ok, []}
    end
  end

  defp settle_giveaway(%{template: %{type: :activity_based, event_type: event_type, winner_count: count, prize_range: {min_prize, max_prize}}, started_at: started_at}) do
    # Get users who performed the activity in the last hour
    active_users = Repo.all(
      from e in BlocksterV2.Notifications.UserEvent,
        where: e.event_type == ^event_type,
        where: e.inserted_at >= ^started_at,
        join: u in User, on: u.id == e.user_id,
        where: not is_nil(u.telegram_user_id),
        where: not is_nil(u.smart_wallet_address),
        group_by: [e.user_id, u.telegram_username],
        select: %{id: e.user_id, telegram_username: u.telegram_username}
    )

    if length(active_users) > 0 do
      winners = active_users
        |> Enum.take_random(min(count, length(active_users)))
        |> Enum.map(fn user ->
          amount = min_prize + :rand.uniform(max_prize - min_prize)
          {user.id, user.telegram_username, amount}
        end)

      Enum.each(winners, fn {user_id, _username, amount} ->
        credit_user(user_id, amount)
        Process.sleep(100)
      end)

      {:ok, winners}
    else
      {:ok, []}
    end
  end

  defp settle_giveaway(%{template: %{type: :new_members, prize_amount: amount}, started_at: started_at}) do
    new_members = Repo.all(
      from u in User,
        where: not is_nil(u.telegram_user_id),
        where: not is_nil(u.smart_wallet_address),
        where: u.telegram_group_joined_at >= ^started_at,
        select: %{id: u.id, telegram_username: u.telegram_username}
    )

    winners = Enum.map(new_members, fn user ->
      credit_user(user.id, amount)
      Process.sleep(100)
      {user.id, user.telegram_username, amount}
    end)

    {:ok, winners}
  end

  defp settle_giveaway(_promo), do: {:ok, []}

  # ======== Competition Settlement ========

  defp settle_competition(%{template: template, started_at: started_at}) do
    leaderboard = get_leaderboard(template.metric, template.event_type, started_at, template.top_n)

    if length(leaderboard) > 0 do
      prizes = distribute_prizes(template.prize_pool, template.distribution, template.top_n, length(leaderboard))

      winners = leaderboard
        |> Enum.zip(prizes)
        |> Enum.map(fn {{user_id, username, _score}, prize} ->
          credit_user(user_id, prize)
          Process.sleep(100)
          {user_id, username, prize}
        end)

      {:ok, winners}
    else
      {:ok, []}
    end
  end

  defp get_leaderboard(metric, event_type, since, limit) do
    case metric do
      :articles_read ->
        Repo.all(
          from e in BlocksterV2.Notifications.UserEvent,
            where: e.event_type == ^event_type,
            where: e.inserted_at >= ^since,
            join: u in User, on: u.id == e.user_id,
            where: not is_nil(u.telegram_user_id),
            where: not is_nil(u.smart_wallet_address),
            group_by: [e.user_id, u.telegram_username],
            select: {e.user_id, u.telegram_username, count(e.id)},
            order_by: [desc: count(e.id)],
            limit: ^limit
        )

      :bet_count ->
        Repo.all(
          from e in BlocksterV2.Notifications.UserEvent,
            where: e.event_type == ^event_type,
            where: e.inserted_at >= ^since,
            join: u in User, on: u.id == e.user_id,
            where: not is_nil(u.telegram_user_id),
            where: not is_nil(u.smart_wallet_address),
            group_by: [e.user_id, u.telegram_username],
            select: {e.user_id, u.telegram_username, count(e.id)},
            order_by: [desc: count(e.id)],
            limit: ^limit
        )

      _ ->
        []
    end
  end

  @doc "Distribute prizes according to model"
  def distribute_prizes(pool, :tiered, top_n, actual_count) do
    count = min(top_n, actual_count)
    case count do
      1 -> [pool]
      2 -> [pool * 0.6, pool * 0.4]
      _ -> [pool * 0.5, pool * 0.3, pool * 0.2]
    end
    |> Enum.take(count)
  end

  def distribute_prizes(pool, :winner_take_all, _top_n, _actual_count) do
    [pool]
  end

  def distribute_prizes(pool, :participation, _top_n, actual_count) when actual_count > 0 do
    share = pool / actual_count
    List.duplicate(share, actual_count)
  end

  def distribute_prizes(_pool, _model, _top_n, _actual_count), do: []

  # ======== Shared Helpers ========

  defp get_eligible_group_members do
    Repo.all(
      from u in User,
        where: not is_nil(u.telegram_user_id),
        where: not is_nil(u.telegram_group_joined_at),
        where: not is_nil(u.smart_wallet_address),
        select: %{id: u.id, telegram_user_id: u.telegram_user_id,
                  telegram_username: u.telegram_username,
                  smart_wallet_address: u.smart_wallet_address}
    )
  end

  defp cleanup_hourly_rules(promo_id) do
    rules = SystemConfig.get("custom_rules", [])

    cleaned = Enum.reject(rules, fn rule ->
      rule["source"] == "telegram_bot" and
        (rule["_promo_id"] == promo_id or rule["_hourly_promo"] == true)
    end)

    if length(cleaned) != length(rules) do
      SystemConfig.put("custom_rules", cleaned, "hourly_promo_bot")
    end
  end

  @doc "Clean up ALL bot-created rules (used when pausing)"
  def cleanup_all_bot_rules do
    rules = SystemConfig.get("custom_rules", [])
    cleaned = Enum.reject(rules, &(&1["source"] == "telegram_bot"))

    if length(cleaned) != length(rules) do
      SystemConfig.put("custom_rules", cleaned, "hourly_promo_bot")
    end
  end

  # ======== Daily Budget Tracking (Mnesia) ========

  defp check_daily_budget(amount) do
    state = get_or_reset_daily_state()
    if state.total_bux_given + amount <= @daily_bux_limit, do: :ok, else: {:error, :daily_budget_exceeded}
  end

  defp check_user_reward_limit(user_id) do
    state = get_or_reset_daily_state()
    count = Map.get(state.user_reward_counts, user_id, 0)
    if count < @max_rewards_per_user_per_day, do: :ok, else: {:error, :user_daily_limit}
  end

  defp record_reward(user_id, amount) do
    state = get_or_reset_daily_state()
    new_total = state.total_bux_given + amount
    new_counts = Map.update(state.user_reward_counts, user_id, 1, &(&1 + 1))
    :mnesia.dirty_write({:bot_daily_rewards, :daily, state.date, new_total, new_counts})
  end

  defp get_or_reset_daily_state do
    today = Date.utc_today()

    case :mnesia.dirty_read(:bot_daily_rewards, :daily) do
      [{:bot_daily_rewards, :daily, ^today, total, counts}] ->
        %{date: today, total_bux_given: total, user_reward_counts: counts}

      _ ->
        # New day or first run — reset
        :mnesia.dirty_write({:bot_daily_rewards, :daily, today, 0, %{}})
        %{date: today, total_bux_given: 0, user_reward_counts: %{}}
    end
  rescue
    _ -> %{date: Date.utc_today(), total_bux_given: 0, user_reward_counts: %{}}
  catch
    :exit, _ -> %{date: Date.utc_today(), total_bux_given: 0, user_reward_counts: %{}}
  end
end
